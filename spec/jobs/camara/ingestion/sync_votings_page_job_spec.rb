# frozen_string_literal: true

require "rails_helper"

RSpec.describe Camara::Ingestion::SyncVotingsPageJob, type: :job do
  self.use_transactional_tests = false
  include ActiveJob::TestHelper

  let!(:sync_run) { create(:camara_ingestion_sync_run, :running) }
  let(:client) { CongregaPlenum::VotingsService }
  let(:ids) { Array.new(100) { "sync-job-#{SecureRandom.uuid}" } }
  let(:payloads) do
    ids.map do |id|
      { "id" => id, "data" => "2026-01-05", "uri" => "https://example.org/votacoes/#{id}" }
    end
  end
  let(:dates) { { start_date: "2026-01-01", end_date: "2026-12-31" } }

  around do |example|
    adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    example.run
  ensure
    ActiveJob::Base.queue_adapter = adapter
  end

  before do
    allow(client).to receive(:fetch_list).and_raise("unexpected voting page request")
  end

  after do
    Camara::Legislation::Voting.where(external_id: ids).delete_all
    sync_run.destroy!
  end

  def source_page(page)
    allow(client).to receive(:fetch_list).with(
      page:, items_per_page: 100, start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 12, 31),
      order: "ASC", order_by: "id"
    )
  end

  def perform_page(page = 1, **overrides)
    described_class.perform_now(sync_run_id: sync_run.id, page:, **dates.merge(overrides))
  end

  it "enqueues the hydration IDs and the next page only after confirming a full page" do
    source_page(1).and_return(payloads)

    expect { perform_page }.to have_enqueued_job(described_class)
      .with(sync_run_id: sync_run.id, page: 2, **dates).on_queue("camara_sync")

    hydration = enqueued_jobs.select { |job| job[:job] == Camara::Legislation::HydrateVotingJob }
    expect(hydration.map { |job| job[:args].first.fetch("external_id") }).to match_array(ids)
    expect(hydration.map { |job| job[:args].first.fetch("sync_run_id") }.uniq).to eq([ sync_run.id ])
    expect(hydration.map { |job| job[:queue] }.uniq).to eq([ "camara_hydration" ])
    expect(sync_run.reload).to have_attributes(page: 1, processed_count: 100, pending_voting_ids: nil)

    clear_enqueued_jobs
    source_page(1).and_raise("a dispatched page must not be fetched again")
    expect { perform_page }.not_to have_enqueued_job
  end

  it "enqueues hydration for a short final page without continuing pagination" do
    source_page(1).and_return([ payloads.first ])

    expect { perform_page }.to have_enqueued_job(Camara::Legislation::HydrateVotingJob)
      .with(external_id: ids.first, sync_run_id: sync_run.id).on_queue("camara_hydration")
    expect(enqueued_jobs.count).to eq(1)
    expect(sync_run.reload).to have_attributes(page: 1, pagination_completed_at: be_present, status: "running")
  end

  it "resumes enqueuing a page committed before the previous worker could dispatch it" do
    source_page(1).and_return([ payloads.first ])
    Camara::Ingestion::PaginateVotings.call(sync_run_id: sync_run.id, page: 1, **dates)
    expect(sync_run.reload.pending_voting_ids).to eq([ ids.first ])
    source_page(1).and_raise("recovery must use the committed IDs")

    expect { perform_page }.to have_enqueued_job(Camara::Legislation::HydrateVotingJob)
      .with(external_id: ids.first, sync_run_id: sync_run.id)
    expect(sync_run.reload).to have_attributes(processed_count: 1, pending_voting_ids: nil)
  end

  it "records a permanent source failure without enqueuing either hydration or another page" do
    source_page(1).and_raise(CongregaPlenum::APIError, "invalid source response")

    expect { perform_page }.to raise_error(CongregaPlenum::APIError)
    expect(enqueued_jobs).to be_empty
    expect(sync_run.reload).to have_attributes(status: "failed", page: nil, error_class: "CongregaPlenum::APIError")
  end

  it "retains the committed IDs and stops the chain if the queue rejects hydration" do
    source_page(1).and_return(payloads)
    allow(ActiveJob::Base.queue_adapter).to receive(:enqueue).and_raise(ActiveJob::EnqueueError, "queue unavailable")

    expect { perform_page }.to raise_error(described_class::EnqueueError, /hydration/)
    expect(enqueued_jobs).to be_empty
    expect(sync_run.reload).to have_attributes(status: "failed", page: 1, pending_voting_ids: ids)
    expect(Camara::Legislation::Voting.where(external_id: ids).count).to eq(100)
  end

  it "retries a transient failure on the same page and records failure after the final attempt" do
    source_page(1).and_raise(CongregaPlenum::ServerError)

    expect { perform_page }.to have_enqueued_job(described_class)
      .with(sync_run_id: sync_run.id, page: 1, **dates).on_queue("camara_sync")
    expect(sync_run.reload).to be_running
    ActiveJob::Base.execute(enqueued_jobs.last)
    expect(sync_run.reload).to be_running
    expect { ActiveJob::Base.execute(enqueued_jobs.last) }.to raise_error(CongregaPlenum::ServerError)
    expect(sync_run.reload).to have_attributes(status: "failed", page: nil)
  end

  it "marks the page limit as a terminal failure after dispatching the last page's hydration" do
    sync_run.update!(filters: sync_run.filters.merge("max_pages" => 1))
    source_page(1).and_return(payloads)

    expect { perform_page }.to raise_error(described_class::PageLimitReached)
    expect(enqueued_jobs.map { |job| job[:job] }.uniq).to eq([ Camara::Legislation::HydrateVotingJob ])
    expect(sync_run.reload).to have_attributes(status: "failed", page: 1, pending_voting_ids: ids)
  end

  it "defers enqueue until commit and uses one Solid Queue concurrency slot per run" do
    first = nil
    ApplicationRecord.transaction do
      first = described_class.perform_later(sync_run_id: sync_run.id, page: 1, **dates)
      expect(enqueued_jobs).to be_empty
    end
    expect(enqueued_jobs.length).to eq(1)
    same_run = described_class.new(sync_run_id: sync_run.id, page: 2, **dates)
    another_run = create(:camara_ingestion_sync_run, :running)
    other = described_class.new(sync_run_id: another_run.id, page: 1, **dates)

    expect(first.concurrency_limit).to eq(1)
    expect(first.concurrency_on_conflict).to eq(:block)
    expect(first.concurrency_key).to eq(same_run.concurrency_key)
    expect(first.concurrency_key).not_to eq(other.concurrency_key)
  ensure
    another_run&.destroy!
  end
end
