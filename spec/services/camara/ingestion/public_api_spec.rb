# frozen_string_literal: true

require "rails_helper"

RSpec.describe Camara::Ingestion::PublicApi do
  it "starts a persisted sync run and returns an immutable snapshot" do
    sync_run = create(:camara_ingestion_sync_run)

    snapshot = described_class.start!(sync_run_id: sync_run.id)

    expect(sync_run.reload.status).to eq("running")
    expect(snapshot).to be_a(described_class::SyncRunSnapshot)
    expect(snapshot).to be_frozen
    expect(snapshot).to have_attributes(
      id: sync_run.id,
      resource: "votings",
      status: "running",
      filters: sync_run.filters,
      processed_count: 0,
      failed_count: 0
    )
    expect(snapshot.filters).to be_frozen
    expect(snapshot.filters.fetch("start_date")).to be_frozen
  end

  it "records progress through the module boundary" do
    sync_run = create(:camara_ingestion_sync_run, :running)

    snapshot = described_class.record_progress!(
      sync_run_id: sync_run.id,
      page: 2,
      processed_count: 100,
      failed_count: 1
    )

    expect(snapshot).to have_attributes(
      status: "running",
      page: 2,
      processed_count: 100,
      failed_count: 1
    )
    expect(sync_run.reload.page).to eq(2)
  end

  it "marks success through the module boundary" do
    sync_run = create(:camara_ingestion_sync_run, :running, processed_count: 100)

    snapshot = described_class.succeed!(sync_run_id: sync_run.id)

    expect(snapshot.status).to eq("succeeded")
    expect(snapshot.finished_at).to be_present
    expect(sync_run.reload).to be_succeeded
  end

  it "marks failure through the module boundary without exposing the model" do
    sync_run = create(:camara_ingestion_sync_run, :running, processed_count: 25)

    snapshot = described_class.fail!(
      sync_run_id: sync_run.id,
      error: RuntimeError.new("upstream contract failed")
    )

    expect(snapshot).to have_attributes(
      status: "failed",
      processed_count: 25,
      error_class: "RuntimeError",
      error_message: "upstream contract failed"
    )
    expect(snapshot).not_to be_a(ActiveRecord::Base)
    expect(sync_run.reload).to be_failed
  end
end
