# frozen_string_literal: true

require "rails_helper"

RSpec.describe Camara::Legislation::Voting, type: :model do
  it "loads the namespaced model and preserves its external identity and provenance" do
    payload = {
      "id" => "2355754-35", "data" => "2026-01-15", "aprovacao" => nil,
      "proposicoesAfetadas" => [ { "id" => 2355754 }, { "id" => 2355755 } ]
    }
    voting = create(:camara_legislation_voting, external_id: "2355754-35", raw_payload: payload)

    expect(described_class.name).to eq("Camara::Legislation::Voting")
    expect(described_class.table_name).to eq("camara_votings")
    expect(voting.reload).to have_attributes(
      external_id: "2355754-35", raw_payload: payload,
      source_uri: "https://dadosabertos.camara.leg.br/api/v2/votacoes/2355754-35",
      approved: nil, registered_at: nil, body_external_id: nil, event_external_id: nil
    )
    expect(voting.id).to be_a(Integer)
    expect(voting.fetched_at).to be_present
  end

  { approved: true, rejected: false, approval_unknown: nil }.each do |trait, result|
    it "persists the #{trait} result without collapsing the tri-state" do
      voting = create(:camara_legislation_voting, trait)

      expect(voting.reload.approved).to eq(result)
    end
  end

  it "preserves optional body, event and description snapshots without related records" do
    attributes = {
      body_external_id: "180", body_acronym: "PLEN",
      body_source_uri: "https://dadosabertos.camara.leg.br/api/v2/orgaos/180",
      event_external_id: "12345",
      event_source_uri: "https://dadosabertos.camara.leg.br/api/v2/eventos/12345",
      description: "Aprovado o requerimento."
    }
    voting = create(:camara_legislation_voting, **attributes)

    expect(voting.reload).to have_attributes(**attributes)
  end

  %i[external_id occurred_on source_uri fetched_at raw_payload].each do |attribute|
    it "rejects a missing #{attribute} on a persisted voting" do
      voting = create(:camara_legislation_voting)

      expect(voting.update(attribute => nil)).to be(false)
      expect(voting.errors[attribute]).to be_present
      expect(voting.reload.public_send(attribute)).to be_present
    end
  end

  it "rejects blank identity and non-object payloads" do
    voting = create(:camara_legislation_voting)

    expect(voting.update(external_id: " ", raw_payload: [ "invalid" ])).to be(false)
    expect(voting.errors).to include(:external_id, :raw_payload)
  end

  it "validates duplicate identity and enforces it in PostgreSQL for bulk writes" do
    original, other = create_list(:camara_legislation_voting, 2)

    expect(other.update(external_id: original.external_id)).to be(false)
    expect(other.errors[:external_id]).to include("has already been taken")
    expect do
      described_class.transaction(requires_new: true) do
        described_class.insert_all!([ original.attributes.except("id") ])
      end
    end.to raise_error(ActiveRecord::RecordNotUnique)
    expect(described_class.where(external_id: original.external_id).count).to eq(1)
  end

  it "indexes the external identity, date, body and event" do
    indexes = described_class.connection.indexes(described_class.table_name)

    expect(indexes.map(&:columns)).to include(
      [ "external_id" ], [ "occurred_on" ], [ "body_external_id" ], [ "event_external_id" ]
    )
    expect(indexes.find { |index| index.columns == [ "external_id" ] }.unique).to be(true)
  end

  it "keeps the occurrence date distinct from the registration instant and persists UTC" do
    Time.use_zone("Brasilia") do
      voting = create(
        :camara_legislation_voting, occurred_on: Date.new(2026, 1, 15),
        registered_at: "2026-01-17T23:30:00", fetched_at: "2026-01-19T10:00:00+02:00"
      )

      expect(voting.reload.occurred_on).to eq(Date.new(2026, 1, 15))
      expect(voting.registered_at.utc).to eq(Time.utc(2026, 1, 18, 2, 30))
      expect(voting.fetched_at.utc).to eq(Time.utc(2026, 1, 19, 8))
      stored = described_class.connection.select_value(
        "SELECT registered_at FROM camara_votings WHERE id = #{Integer(voting.id)}"
      )
      expect(stored).to eq(Time.utc(2026, 1, 18, 2, 30))
    end
  end

  it "composes inclusive period, body and known-result filters" do
    first = create(:camara_legislation_voting, :approved, occurred_on: Date.new(2026, 1, 1), body_external_id: "180")
    last = create(:camara_legislation_voting, :rejected, occurred_on: Date.new(2026, 1, 31), body_external_id: "180")
    unknown = create(:camara_legislation_voting, :approval_unknown, body_external_id: "180")
    other_body = create(:camara_legislation_voting, :approved, body_external_id: "200")
    outside = create(:camara_legislation_voting, :approved, occurred_on: Date.new(2026, 2, 1), body_external_id: "180")
    period = Date.new(2026, 1, 1)..Date.new(2026, 1, 31)

    expect(described_class.during(period)).to contain_exactly(first, last, unknown, other_body)
    expect(described_class.for_body("180")).to contain_exactly(first, last, unknown, outside)
    expect(described_class.with_known_result).to contain_exactly(first, last, other_body, outside)
    expect(described_class.during(period).for_body("180").with_known_result).to contain_exactly(first, last)
  end

  describe "concurrent creation" do
    self.use_transactional_tests = false

    it "allows only one committed voting for the same external identity" do
      external_id = "race-#{SecureRandom.uuid}"
      ready = Queue.new
      start = Queue.new
      threads = 2.times.map do
        Thread.new do
          described_class.connection_pool.with_connection do
            ready << true
            start.pop
            begin
              create(:camara_legislation_voting, external_id:)
              :created
            rescue ActiveRecord::RecordNotUnique
              :duplicate
            rescue ActiveRecord::RecordInvalid => error
              raise unless error.record.errors.of_kind?(:external_id, :taken)

              :duplicate
            end
          end
        end
      end
      2.times { ready.pop }
      2.times { start << true }

      expect(threads.map(&:value)).to contain_exactly(:created, :duplicate)
      expect(described_class.where(external_id:).count).to eq(1)
    ensure
      threads&.each(&:join)
      described_class.where(external_id:).delete_all if external_id
    end
  end
end
