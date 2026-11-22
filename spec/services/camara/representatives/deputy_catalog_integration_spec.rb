# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Camara deputy catalogue" do
  self.use_transactional_tests = false
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  let(:client) { CongregaPlenum::Client.instance }
  let(:fixtures) { JSON.parse(Rails.root.join("spec/fixtures/camara/representatives/deputies.json").read) }
  let(:first_listing) { fixtures.fetch("first_listing") }
  let(:second_listing) { fixtures.fetch("second_listing") }
  let(:detail) { fixtures.fetch("detail") }
  let(:deputies) { Camara::Representatives::Deputy.where(external_id: "10001") }
  let(:runs) { Camara::Ingestion::SyncRun.where(resource: "deputies") }

  before { allow(client).to receive(:get).and_raise("unexpected Câmara request") }

  after do
    deputies.delete_all
    runs.delete_all
  end

  def start(**options)
    Camara::Ingestion::StartRepresentativeSync.call(resource: :deputies, **options)
  end

  def source_page(page, rows, legislature: 56, links: [])
    allow(client).to receive(:get).with("deputados",
      { idLegislatura: legislature, itens: 100, ordem: "ASC", ordenarPor: "id", pagina: page })
      .and_return("dados" => rows, "links" => links)
  end

  def source_detail(payload)
    allow(client).to receive(:get).with("deputados/10001", {}).and_return("dados" => payload)
  end

  def drain
    ActiveJob::Base.execute(enqueued_jobs.shift) until enqueued_jobs.empty?
  end

  it "keeps one deputy identity and all distinct rows across pages and reimports" do
    continuation = { "rel" => "next", "href" => "https://example.org/deputados?idLegislatura=56&pagina=2" }
    source_page(1, [ first_listing, second_listing ], links: [ continuation ])
    source_page(2, [ second_listing.to_a.reverse.to_h ])
    first = Time.utc(2026, 9, 1, 12)

    travel_to(first) do
      result = start(legislature_id: 56)
      expect(start(legislature_id: "56")).to have_attributes(sync_run_id: result.sync_run_id, error: :already_active)
      drain
      expect(runs.find(result.sync_run_id)).to have_attributes(status: "succeeded", page: 2, processed_count: 3)
    end
    deputy = deputies.sole
    expect(deputy).to have_attributes(party_acronym: nil, electoral_name: nil, fetched_at: nil)
    expect(deputy.listing_observations.pluck(:raw_payload)).to contain_exactly(first_listing, second_listing)

    travel_to(first + 1.day) do
      start(legislature_id: 56)
      drain
    end
    expect(deputies.sole).to eq(deputy)
    expect(deputy.listing_observations.count).to eq(2)
    expect(deputy.listing_observations.pluck(:first_seen_at, :last_seen_at).uniq).to eq([ [ first, first + 1.day ] ])

    source_page(1, [ first_listing ], legislature: 57)
    start(legislature_id: 57)
    drain
    expect(deputy.listing_observations.pluck(:legislature_external_id)).to contain_exactly("56", "56", "57")
  end

  it "updates current detail independently without changing the published vote snapshot" do
    vote = create(:camara_legislation_vote, deputy_external_id: "10001", party_acronym: "PFX", legislature_external_id: "56")
    vote_payload = vote.raw_payload
    source_page(1, [ first_listing, second_listing ])
    start(legislature_id: 56)
    drain
    deputy = deputies.sole

    source_detail(detail)
    detail_run = start(external_id: 10001)
    drain
    expect(runs.find(detail_run.sync_run_id)).to have_attributes(status: "succeeded", page: nil, processed_count: 1)
    expect(deputy.reload).to have_attributes(electoral_name: "Deputada Exemplo", party_acronym: "PFZ", situation: "Exercício")

    departed = detail.merge("ultimoStatus" => detail.fetch("ultimoStatus").merge("situacao" => "Fim de Mandato"))
    source_detail(departed)
    start(external_id: 10001)
    drain
    start(legislature_id: 56)
    drain
    expect(deputy.reload).to have_attributes(raw_payload: departed, party_acronym: "PFZ", situation: "Fim de Mandato")
    expect(deputies.with_electoral_name("deputada exemplo").from_state("SP").with_situation("Fim de Mandato")).to contain_exactly(deputy)
    expect(vote.reload).to have_attributes(raw_payload: vote_payload, party_acronym: "PFX", state_acronym: "DF", legislature_external_id: "56")
  ensure
    vote&.voting&.destroy!
  end

  it "keeps an identity when detail is unavailable and rejects an unscoped catalogue" do
    expect { start }.to raise_error(ArgumentError, /positive external ID/)
    expect(enqueued_jobs).to be_empty
    source_page(1, [ first_listing ])
    start(legislature_id: 56)
    drain
    deputy = deputies.sole

    source_detail(nil)
    detail_run = start(external_id: 10001)
    expect { drain }.to raise_error(Camara::Representatives::Mappers::ContractError)
    expect(runs.find(detail_run.sync_run_id)).to be_failed
    expect(deputy.reload).to have_attributes(fetched_at: nil)
    expect(deputy.listing_observations.sole.raw_payload).to eq(first_listing)
  end
end
