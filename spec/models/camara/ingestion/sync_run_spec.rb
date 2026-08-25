# frozen_string_literal: true

require "rails_helper"

RSpec.describe Camara::Ingestion::SyncRun, type: :model do
  describe "persistence" do
    it "uses the stable table name and operational indexes" do
      expect(described_class.table_name).to eq("camara_sync_runs")

      indexed_columns = described_class.connection.indexes(described_class.table_name).map(&:columns)
      expect(indexed_columns).to include([ "resource" ], [ "status" ], [ "created_at" ])
    end

    it "persists the original filters and starts with zeroed progress" do
      filters = {
        "start_date" => "2026-01-01",
        "end_date" => "2026-12-31",
        "body_ids" => [ 1, 2 ]
      }
      sync_run = create(:camara_ingestion_sync_run, filters:)

      expect(sync_run.reload).to have_attributes(
        resource: "votings",
        status: "pending",
        filters: filters,
        processed_count: 0,
        failed_count: 0,
        started_at: nil,
        finished_at: nil
      )
    end
  end

  describe "validations" do
    it "requires a supported resource and its minimum filter schema" do
      unsupported = build(:camara_ingestion_sync_run, resource: "unknown")
      incomplete = build(:camara_ingestion_sync_run, filters: { "start_date" => "2026-01-01" })
      non_object = build(:camara_ingestion_sync_run, filters: [ "2026-01-01" ])

      expect(unsupported).not_to be_valid
      expect(incomplete).not_to be_valid
      expect(incomplete.errors[:filters]).to include("must include end_date for votings")
      expect(non_object).not_to be_valid
      expect(non_object.errors[:filters]).to include("must be a JSON object")
    end

    it "rejects invalid pages and counters" do
      sync_run = build(
        :camara_ingestion_sync_run,
        page: 0,
        processed_count: -1,
        failed_count: -1
      )

      expect(sync_run).not_to be_valid
      expect(sync_run.errors).to include(:page, :processed_count, :failed_count)
    end

    it "requires timestamps and diagnostics consistent with the status" do
      running_without_start = build(:camara_ingestion_sync_run, status: "running")
      succeeded_without_finish = build(:camara_ingestion_sync_run, :running, status: "succeeded")
      failed_without_error = build(
        :camara_ingestion_sync_run,
        :running,
        status: "failed",
        finished_at: Time.current
      )

      expect(running_without_start).not_to be_valid
      expect(succeeded_without_finish).not_to be_valid
      expect(failed_without_error).not_to be_valid
      expect(failed_without_error.errors).to include(:error_class, :error_message)
    end
  end

  describe "transitions" do
    it "starts a pending run" do
      sync_run = create(:camara_ingestion_sync_run)

      expect { sync_run.start! }
        .to change(sync_run, :status).from("pending").to("running")

      expect(sync_run.started_at).to be_present
      expect(sync_run.finished_at).to be_nil
    end

    it "records absolute progress without clearing omitted checkpoint values" do
      sync_run = create(:camara_ingestion_sync_run, :running)

      sync_run.record_progress!(
        page: 2,
        cursor: "next-page-token",
        processed_count: 100,
        failed_count: 2
      )
      sync_run.record_progress!(page: 3, processed_count: 150)

      expect(sync_run.reload).to have_attributes(
        page: 3,
        cursor: "next-page-token",
        processed_count: 150,
        failed_count: 2,
        status: "running",
        finished_at: nil
      )
    end

    it "does not allow numeric progress to move backwards" do
      sync_run = create(
        :camara_ingestion_sync_run,
        :running,
        page: 3,
        processed_count: 150,
        failed_count: 2
      )

      expect { sync_run.record_progress!(page: 2) }
        .to raise_error(described_class::InvalidProgress, "page cannot move backwards")
      expect { sync_run.record_progress!(processed_count: 149) }
        .to raise_error(described_class::InvalidProgress, "processed_count cannot move backwards")
      expect { sync_run.record_progress!(failed_count: 1) }
        .to raise_error(described_class::InvalidProgress, "failed_count cannot move backwards")
    end

    it "completes a running run with coherent timestamps and counters" do
      sync_run = create(:camara_ingestion_sync_run, :running, processed_count: 100)

      sync_run.succeed!

      expect(sync_run.reload).to have_attributes(
        status: "succeeded",
        processed_count: 100,
        failed_count: 0,
        error_class: nil,
        error_message: nil
      )
      expect(sync_run.finished_at).to be >= sync_run.started_at
    end

    it "fails a running run while preserving request and progress" do
      filters = {
        "start_date" => "2026-01-01",
        "end_date" => "2026-12-31",
        "body_ids" => [ 1, 2 ]
      }
      sync_run = create(
        :camara_ingestion_sync_run,
        :running,
        filters:,
        page: 4,
        processed_count: 175,
        failed_count: 3
      )
      error = RuntimeError.new(
        "request failed token=secret-token password:super-secret authorization=Bearer-token"
      )
      error.set_backtrace([ "/private/path/with/token" ])

      sync_run.fail!(error:)

      expect(sync_run.reload).to have_attributes(
        status: "failed",
        filters: filters,
        page: 4,
        processed_count: 175,
        failed_count: 3,
        error_class: "RuntimeError",
        error_message: "request failed token=[FILTERED] password:[FILTERED] authorization=[FILTERED]"
      )
      expect(sync_run.finished_at).to be >= sync_run.started_at
      expect(sync_run.attributes).not_to have_key("backtrace")
    end

    it "rejects transitions from an incompatible state" do
      pending_sync_run = create(:camara_ingestion_sync_run)
      running_sync_run = create(:camara_ingestion_sync_run, :running)
      succeeded_sync_run = create(:camara_ingestion_sync_run, :succeeded)
      failed_sync_run = create(:camara_ingestion_sync_run, :failed)

      expect { pending_sync_run.record_progress!(page: 1) }
        .to raise_error(described_class::InvalidTransition)
      expect { pending_sync_run.succeed! }
        .to raise_error(described_class::InvalidTransition)
      expect { pending_sync_run.fail!(error: RuntimeError.new("early failure")) }
        .to raise_error(described_class::InvalidTransition)
      expect { running_sync_run.start! }
        .to raise_error(described_class::InvalidTransition)

      [ succeeded_sync_run, failed_sync_run ].each do |terminal_sync_run|
        expect { terminal_sync_run.start! }
          .to raise_error(described_class::InvalidTransition)
        expect { terminal_sync_run.record_progress!(page: 5) }
          .to raise_error(described_class::InvalidTransition)
        expect { terminal_sync_run.succeed! }
          .to raise_error(described_class::InvalidTransition)
        expect { terminal_sync_run.fail!(error: RuntimeError.new("late failure")) }
          .to raise_error(described_class::InvalidTransition)
      end
    end
  end
end
