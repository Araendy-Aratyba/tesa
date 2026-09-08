# frozen_string_literal: true

require "rails_helper"

RSpec.describe Camara::Legislation::Vote, type: :model do
  it "persists the recorded position, instant and published deputy snapshot" do
    vote = create(:camara_legislation_vote, :obstruction)

    expect(vote.reload).to have_attributes(
      position: "Obstrução",
      deputy_external_id: vote.deputy_external_id,
      deputy_name: "Parlamentar Exemplo",
      party_acronym: "PARTIDO",
      state_acronym: "DF",
      legislature_external_id: "57",
      deputy_email: "dep.exemplo@camara.leg.br"
    )
    expect(vote.recorded_at).to be_present
    expect(vote.deputy_source_uri).to end_with("/#{vote.deputy_external_id}")
    expect(vote.raw_payload.dig("deputado_", "nome")).to eq("Parlamentar Exemplo")
  end

  it "does not require a Representatives record or a known position value" do
    payload = { "tipoVoto" => "Posição futura", "campoNovo" => { "valor" => 1 } }
    vote = create(
      :camara_legislation_vote,
      position: "Posição futura",
      raw_payload: payload
    )
    unknown = create(:camara_legislation_vote, :position_unknown, voting: vote.voting)
    blank = create(:camara_legislation_vote, position: "", voting: vote.voting)

    expect(vote.reload.raw_payload).to eq(payload)
    expect(vote.position).to eq("Posição futura")
    expect(unknown.reload.position).to be_nil
    expect(blank.reload.position).to eq("")
  end

  %i[voting deputy_external_id fetched_at raw_payload].each do |attribute|
    it "rejects a missing #{attribute}" do
      vote = create(:camara_legislation_vote)

      expect(vote.update(attribute => nil)).to be(false)
      expect(vote.errors[attribute]).to be_present
      expect(vote.reload.public_send(attribute)).to be_present
    end
  end

  it "rejects a non-object raw payload" do
    vote = create(:camara_legislation_vote)

    expect(vote.update(raw_payload: [ "invalid" ])).to be(false)
    expect(vote.errors[:raw_payload]).to include("must be a JSON object")
    expect(vote.reload.raw_payload).to be_a(Hash)
  end

  it "enforces one vote per deputy and voting in validations and PostgreSQL" do
    voting = create(:camara_legislation_voting)
    vote, other = create_list(:camara_legislation_vote, 2, voting:)

    expect(other.update(deputy_external_id: vote.deputy_external_id)).to be(false)
    expect(other.errors[:deputy_external_id]).to include("has already been taken")

    same_deputy_elsewhere = create(
      :camara_legislation_vote,
      deputy_external_id: vote.deputy_external_id
    )
    expect(same_deputy_elsewhere).to be_persisted

    expect do
      described_class.insert_all!([ vote.attributes.except("id") ])
    end.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "updates a reimported vote through the composite identity without duplicating it" do
    vote = create(:camara_legislation_vote, position: "Sim")
    newer_payload = vote.raw_payload.merge("tipoVoto" => "Não", "campoNovo" => true)

    described_class.upsert_all(
      [
        vote.attributes.except("id", "created_at", "updated_at").merge(
          "position" => "Não",
          "raw_payload" => newer_payload,
          "fetched_at" => 1.hour.from_now
        )
      ],
      unique_by: :index_camara_votes_identity
    )

    expect(described_class.where(voting: vote.voting, deputy_external_id: vote.deputy_external_id).count).to eq(1)
    expect(vote.reload).to have_attributes(position: "Não", raw_payload: newer_payload)
  end

  it "has the indexes required for identity and filtering" do
    indexes = described_class.connection.indexes(described_class.table_name)

    identity = indexes.find { |index| index.name == "index_camara_votes_identity" }
    expect(identity.columns).to eq(%w[voting_id deputy_external_id])
    expect(identity.unique).to be(true)
    expect(indexes.map(&:columns)).to include([ "deputy_external_id" ], [ "position" ])
  end
end
