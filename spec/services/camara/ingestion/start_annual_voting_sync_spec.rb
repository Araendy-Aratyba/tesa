# frozen_string_literal: true

require "rails_helper"

RSpec.describe Camara::Ingestion::StartAnnualVotingSync do
  self.use_transactional_tests = false
  include ActiveJob::TestHelper

  let(:year) { "2025" }
  let(:filters) { { "start_date" => "#{year}-01-01", "end_date" => "#{year}-12-31" } }
  let(:runs) { Camara::Ingestion::SyncRun.where("filters @> ?::jsonb", filters.to_json) }

  before do
    allow(CongregaPlenum::VotingsService).to receive(:fetch_list).and_raise("unexpected Câmara request")
  end

  after { runs.delete_all }

  it "commits the annual interval and enqueues exactly the first page" do
    result = nil
    expect { result = described_class.call(year:) }.to change(runs, :count).by(1)
      .and have_enqueued_job(Camara::Ingestion::SyncVotingsPageJob).once.on_queue("camara_sync")

    run = runs.sole
    expect(run).to have_attributes(resource: "votings", status: "running", filters:, started_at: be_present, page: nil)
    expect(result).to have_attributes(sync_run_id: run.id, status: :running, error: nil)
    expect(enqueued_jobs.first.fetch(:args).first).to include(
      "sync_run_id" => run.id, "page" => 1, "start_date" => "2025-01-01", "end_date" => "2025-12-31"
    )
  end

  it "rejects missing, malformed and unsupported years before writing or enqueuing" do
    invalid_years = [ nil, "25", "2025.0", "02025", "1934", (Date.current.year + 1).to_s ]

    expect do
      invalid_years.each do |invalid_year|
        expect(described_class.call(year: invalid_year)).to have_attributes(
          sync_run_id: nil, status: nil, error: :invalid_year
        )
      end
    end.not_to change(Camara::Ingestion::SyncRun, :count)
    expect(enqueued_jobs).to be_empty
  end

  %i[pending running].each do |status|
    it "returns the existing #{status} run for the same full-year interval" do
      run = if status == :running
        create(:camara_ingestion_sync_run, :running, filters: filters.merge("max_pages" => 1000))
      else
        create(:camara_ingestion_sync_run, filters:)
      end

      expect { expect(described_class.call(year:)).to have_attributes(
        sync_run_id: run.id, status:, error: :already_active
      ) }.not_to change(runs, :count)
      expect(enqueued_jobs).to be_empty
    end
  end

  it "starts a new run after an annual run becomes terminal" do
    finished = create(:camara_ingestion_sync_run, :succeeded, filters:)
    result = described_class.call(year:)

    expect(result).to have_attributes(status: :running, error: nil)
    expect(result.sync_run_id).not_to eq(finished.id)
    expect(enqueued_jobs.size).to eq(1)
  end

  it "enqueues only once for concurrent starts of the same year" do
    ready = Queue.new
    start = Queue.new
    threads = Array.new(2) do
      Thread.new do
        ready << true
        start.pop
        described_class.call(year:)
      end
    end
    2.times { ready.pop }
    2.times { start << true }
    results = threads.map(&:value)

    expect(results.map(&:error)).to contain_exactly(nil, :already_active)
    expect(results.map(&:sync_run_id).uniq).to eq([ runs.sole.id ])
    expect(enqueued_jobs.size).to eq(1)
  end

  [ ActiveJob::EnqueueError, SolidQueue::Job::EnqueueError ].each do |error_class|
    it "records #{error_class} as a failed run so it can be started again" do
      allow(ActiveJob::Base.queue_adapter).to receive(:enqueue).and_raise(error_class, "queue unavailable")

      result = described_class.call(year:)

      expect(runs.sole).to have_attributes(id: result.sync_run_id, status: "failed", error_class: error_class.name)
      expect(result).to have_attributes(status: :failed, error: :enqueue_failed)
      expect(enqueued_jobs).to be_empty

      allow(ActiveJob::Base.queue_adapter).to receive(:enqueue).and_call_original
      expect { described_class.call(year:) }.to have_enqueued_job(Camara::Ingestion::SyncVotingsPageJob).once
      expect(runs.pluck(:status)).to contain_exactly("failed", "running")
    end
  end
end
