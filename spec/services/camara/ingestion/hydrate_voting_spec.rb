# frozen_string_literal: true

require "rails_helper"

RSpec.describe Camara::Ingestion::HydrateVoting do
  self.use_transactional_tests = false
  include ActiveSupport::Testing::TimeHelpers

  let!(:voting) { create(:camara_legislation_voting) }
  let(:client) { CongregaPlenum::Client.instance }
  let(:endpoint) { "votacoes/#{voting.external_id}" }
  let(:detail) do
    voting.raw_payload.merge(
      "descricao" => "Resultado detalhado", "aprovacao" => 1, "idOrgao" => 123, "idEvento" => 456,
      "proposicoesAfetadas" => [ { "id" => 890 } ]
    )
  end
  let(:vote) { { "tipoVoto" => "Sim", "deputado_" => { "id" => 999 } } }
  let(:orientation) { { "orientacaoVoto" => "Liberado", "codTipoLideranca" => "G", "siglaPartidoBloco" => "Governo" } }

  before do
    allow(client).to receive(:get).and_raise("unexpected Câmara request")
  end

  after { voting.destroy! }

  def hydrate
    described_class.call(external_id: voting.external_id)
  end

  def responses(detail: self.detail, votes: [ vote ], orientations: [ orientation ])
    allow(client).to receive(:get).with(endpoint, {}).and_return("dados" => detail)
    allow(client).to receive(:get).with("#{endpoint}/votos", {}).and_return("dados" => votes)
    allow(client).to receive(:get).with("#{endpoint}/orientacoes", {}).and_return("dados" => orientations)
  end

  it "fetches the three resources outside the transaction and records their counts and timestamps" do
    responses
    allow(client).to receive(:get).with("#{endpoint}/votos", {}) do
      expect(ApplicationRecord.current_transaction).not_to be_open
      { "dados" => [ vote ] }
    end
    summary = voting.raw_payload

    result = hydrate

    expect(result).to have_attributes(external_id: voting.external_id, status: :hydrated)
    expect(result.detail).to have_attributes(count: 1, hydrated_at: be_present)
    expect(result.votes).to have_attributes(count: 1, hydrated_at: be_present)
    expect(result.orientations).to have_attributes(count: 1, hydrated_at: be_present)
    expect(voting.reload).to have_attributes(
      approved: true, raw_payload: summary, detail_raw_payload: detail,
      detail_hydrated_at: be_present, votes_hydrated_at: be_present, orientations_hydrated_at: be_present
    )
    expect(voting.votes.first.deputy_external_id).to eq("999")
    expect(voting.orientations.first.position).to eq("Liberado")
  end

  it "idempotently adjusts corrections and removes only children missing from complete responses" do
    old_vote = create(:camara_legislation_vote, voting:)
    old_orientation = create(:camara_legislation_orientation, voting:)
    other_vote = create(:camara_legislation_vote)
    responses
    hydrate
    current_vote = voting.votes.find_by!(deputy_external_id: "999")

    responses(votes: [ vote.merge("tipoVoto" => "Não") ], orientations: [ orientation.merge("orientacaoVoto" => "Sim") ])
    hydrate

    expect(voting.votes.reload).to contain_exactly(current_vote)
    expect(current_vote.reload.position).to eq("Não")
    expect(voting.orientations.reload.pluck(:position)).to eq([ "Sim" ])
    expect(Camara::Legislation::Vote.exists?(old_vote.id)).to be(false)
    expect(Camara::Legislation::Orientation.exists?(old_orientation.id)).to be(false)
    expect(Camara::Legislation::Vote.exists?(other_vote.id)).to be(true)
  ensure
    other_vote&.voting&.destroy!
  end

  it "accepts explicitly empty collections and clears obsolete published children" do
    create(:camara_legislation_vote, voting:)
    create(:camara_legislation_orientation, voting:)
    responses(votes: [], orientations: [])

    result = hydrate

    expect(result.votes.count).to eq(0)
    expect(result.orientations.count).to eq(0)
    expect(voting.reload).to have_attributes(votes_hydrated_at: be_present, orientations_hydrated_at: be_present)
    expect(voting.votes).to be_empty
    expect(voting.orientations).to be_empty
  end

  it "reports the failed endpoint and keeps existing data on a network failure" do
    old_vote = create(:camara_legislation_vote, voting:)
    responses
    allow(client).to receive(:get).with("#{endpoint}/votos", {}).and_raise(CongregaPlenum::ServerError)

    expect { hydrate }.to raise_error(described_class::FetchError) do |error|
      expect(error).to have_attributes(resource: :votes, fetched_resources: [ :detail ])
      expect(error.cause).to be_a(CongregaPlenum::ServerError)
    end
    expect(voting.reload).to have_attributes(detail_raw_payload: nil, votes_hydrated_at: nil)
    expect(voting.votes).to contain_exactly(old_vote)
  end

  [ {}, { "dados" => nil }, { "dados" => [], "links" => [ { "rel" => "next" } ] } ].each do |invalid|
    it "rejects missing, null or incomplete data (#{invalid.keys.join(', ')} with #{invalid['dados'].class})" do
      old_vote = create(:camara_legislation_vote, voting:)
      responses
      allow(client).to receive(:get).with("#{endpoint}/votos", {}).and_return(invalid)

      expect { hydrate }.to raise_error(described_class::FetchError) do |error|
        expect(error.resource).to eq(:votes)
      end
      expect(voting.reload.votes).to contain_exactly(old_vote)
      expect(voting.votes_hydrated_at).to be_nil
    end
  end

  it "rejects invalid identities before writing any resource" do
    responses(votes: [ vote, vote ])
    expect { hydrate }.to raise_error(Camara::Legislation::Mappers::ContractError, /votes\.deputy_external_id/)
    expect(voting.reload.detail_hydrated_at).to be_nil

    responses(detail: detail.merge("id" => "other-voting"))
    expect { hydrate }.to raise_error(Camara::Legislation::Mappers::ContractError, /voting\.id/)
    expect(voting.reload.detail_hydrated_at).to be_nil
  end

  it "rolls back the updated detail and reconciled votes when writing orientations fails" do
    old_vote = create(:camara_legislation_vote, voting:)
    old_orientation = create(:camara_legislation_orientation, voting:)
    responses(orientations: [ orientation.merge("campoNovo" => "\0") ])

    expect { hydrate }.to raise_error(ActiveRecord::StatementInvalid)
    expect(voting.reload).to have_attributes(detail_hydrated_at: nil, votes_hydrated_at: nil, detail_raw_payload: nil)
    expect(voting.votes).to contain_exactly(old_vote)
    expect(voting.orientations).to contain_exactly(old_orientation)
  end

  it "retains hydration data and detail-only identifiers during a subsequent summary import" do
    responses
    hydrate
    summary = voting.raw_payload.merge("descricao" => "Resumo atualizado")
    Camara::Legislation::PublicApi.import_votings_page(payloads: [ summary ], fetched_at: Time.current)

    expect(voting.reload).to have_attributes(
      raw_payload: summary, detail_raw_payload: detail, body_external_id: "123",
      event_external_id: "456", detail_hydrated_at: be_present
    )
  end

  it "keeps a more recent hydration if an older observation arrives out of order" do
    responses
    recent = Time.utc(2026, 9, 1, 12)
    travel_to(recent) { hydrate }

    responses(votes: [], orientations: [])
    travel_to(recent - 1.minute) do
      expect(hydrate).to have_attributes(status: :superseded)
    end

    expect(voting.reload.votes_hydrated_at).to eq(recent)
    expect(voting.votes.count).to eq(1)
    expect(voting.orientations.count).to eq(1)
  end
end
