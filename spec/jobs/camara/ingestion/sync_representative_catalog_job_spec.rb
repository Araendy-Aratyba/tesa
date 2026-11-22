# frozen_string_literal: true

require "rails_helper"

RSpec.describe Camara::Ingestion::SyncRepresentativeCatalogJob, type: :job do
  self.use_transactional_tests = false
  include ActiveJob::TestHelper

  let(:client) { CongregaPlenum::Client.instance }
  let(:entries) { JSON.parse(Rails.root.join("spec/fixtures/camara/representatives/legislatures.json").read) }
  let(:runs) { Camara::Ingestion::SyncRun.where(resource: "legislatures") }
  let(:legislatures) { Camara::Representatives::Legislature.where(external_id: %w[1 57]) }

  before { allow(client).to receive(:get).and_raise("unexpected Câmara request") }

  after do
    runs.delete_all
    legislatures.delete_all
  end

  def page(number)
    allow(client).to receive(:get).with("legislaturas", { itens: 50, pagina: number })
  end

  def start(**options)
    Camara::Ingestion::StartRepresentativeSync.call(resource: :legislatures, **options)
  end

  def drain
    ActiveJob::Base.execute(enqueued_jobs.shift) until enqueued_jobs.empty?
  end

  it "commits both pages, follows an explicit continuation, and counts each page once" do
    link = { "rel" => "next", "href" => "https://example.org/legislaturas?pagina=2" }
    page(1).and_return("dados" => [ entries.first ], "links" => [ link ])
    page(2).and_return("dados" => [ entries.last ], "links" => [])
    first = start
    expect(start).to have_attributes(sync_run_id: first.sync_run_id, error: :already_active)

    drain
    records = legislatures.to_a
    expect(runs.sole).to have_attributes(status: "succeeded", page: 2, processed_count: 2, pagination_completed_at: be_present)
    expect(records.map(&:number)).to contain_exactly(1, 57)
    expect(records.map(&:election_year)).to eq([ nil, nil ])

    replay = start
    drain
    expect(legislatures).to match_array(records)
    expect(runs.find(replay.sync_run_id)).to have_attributes(status: "succeeded", processed_count: 2)
  end

  it "reschedules transient failures and preserves the checkpoint on an invalid continuation response" do
    link = { "rel" => "next", "href" => "https://example.org/legislaturas?pagina=2" }
    page(1).and_return("dados" => [ entries.first ], "links" => [ link ])
    page(2).and_raise(CongregaPlenum::ServerError)
    run = runs.find(start.sync_run_id)
    ActiveJob::Base.execute(enqueued_jobs.shift)
    ActiveJob::Base.execute(enqueued_jobs.shift)
    expect(run.reload).to have_attributes(status: "running", page: 1, processed_count: 1)
    expect(enqueued_jobs.sole[:at]).to be > Time.current.to_f

    page(2).and_return("links" => [])
    expect { drain }.to raise_error(CongregaPlenum::APIError)
    expect(run.reload).to have_attributes(status: "failed", page: 1, processed_count: 1, pagination_completed_at: nil)
    expect(legislatures.pluck(:external_id)).to eq([ "1" ])
  end

  it "audits details separately and keeps the last valid catalogue when a later detail fails" do
    allow(client).to receive(:get).with("legislaturas/57", {}).and_return("dados" => entries.last)
    run = runs.find(start(external_id: 57).sync_run_id)
    expect(enqueued_jobs.sole[:queue]).to eq("camara_hydration")
    drain
    original = legislatures.sole
    expect(run.reload).to have_attributes(status: "succeeded", processed_count: 1)

    allow(client).to receive(:get).with("legislaturas/57", {}).and_return("dados" => entries.first)
    failure = runs.find(start(external_id: 57).sync_run_id)
    expect { drain }.to raise_error(Camara::Representatives::Mappers::ContractError)
    expect(failure.reload).to be_failed
    expect(original.reload.raw_payload).to eq(entries.last)
    expect(legislatures.count).to eq(1)
  end
end
