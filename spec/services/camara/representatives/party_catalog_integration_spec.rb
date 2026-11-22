# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Camara party catalogue" do
  self.use_transactional_tests = false
  include ActiveJob::TestHelper

  let(:client) { CongregaPlenum::Client.instance }
  let(:fixtures) { JSON.parse(Rails.root.join("spec/fixtures/camara/representatives/parties.json").read) }
  let(:summary) { fixtures.fetch("summary") }
  let(:detail) { fixtures.fetch("retired_detail") }
  let(:ingestion) { Camara::Ingestion::PublicApi }
  let(:parties) { Camara::Representatives::Party.where(external_id: %w[36898 36899]) }

  before { allow(client).to receive(:get).and_raise("unexpected Câmara request") }

  after do
    parties.delete_all
    Camara::Ingestion::SyncRun.where(resource: "parties").delete_all
  end

  def sync(**options)
    run = Camara::Ingestion::StartRepresentativeSync.call(resource: :parties, **options)
    ActiveJob::Base.execute(enqueued_jobs.shift) until enqueued_jobs.empty?
    ingestion.fetch(sync_run_id: run.sync_run_id)
  end

  def source_list(rows)
    allow(client).to receive(:get).with("partidos", { itens: 100, ordem: "ASC", ordenarPor: "id", pagina: 1 })
      .and_return("dados" => rows, "links" => [])
  end

  it "imports list and detail independently, retaining identity and status after a rename" do
    source_list([ summary ])
    expect(sync).to have_attributes(status: "succeeded", page: 1, processed_count: 1)
    party = parties.sole
    expect(party).to have_attributes(raw_payload: summary, detail_fetched_at: nil)

    allow(client).to receive(:get).with("partidos/36898", {}).and_return("dados" => detail)
    expect(sync(external_id: 36898)).to have_attributes(status: "succeeded", processed_count: 1, page: nil)
    corrected = summary.merge("sigla" => "PFY", "nome" => "Partido Renomeado")
    other = corrected.merge("id" => 36899, "uri" => "https://dadosabertos.camara.leg.br/api/v2/partidos/36899")
    source_list([ corrected, other ])
    expect(sync).to have_attributes(status: "succeeded", processed_count: 2)

    expect(parties.where(acronym: "PFY").count).to eq(2)
    expect(party.reload).to have_attributes(name: "Partido Renomeado", situation: "Extinto", raw_payload: corrected,
      detail_raw_payload: detail, detail_fetched_at: be_present)
  end

  it "keeps an imported party when detail is missing or the party is absent from a later list" do
    source_list([ summary ])
    sync
    original = parties.sole
    source_list([])
    expect(sync).to have_attributes(status: "succeeded", processed_count: 0)
    allow(client).to receive(:get).with("partidos/36898", {}).and_return("dados" => nil)

    expect { sync(external_id: 36898) }.to raise_error(Camara::Representatives::Mappers::ContractError)
    expect(Camara::Ingestion::SyncRun.where(resource: "parties", status: :failed).count).to eq(1)
    expect(parties.sole).to eq(original)
    expect(original.reload.detail_fetched_at).to be_nil
  end
end
