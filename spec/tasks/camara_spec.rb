# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "camara:sync_votings" do
  self.use_transactional_tests = false
  include ActiveJob::TestHelper

  let(:task) { Rake::Task["camara:sync_votings"] }
  let(:runs) { Camara::Ingestion::SyncRun.where("filters ->> 'start_date' = ?", "2024-01-01") }

  around do |example|
    Rake.with_application do
      Rails.application.load_tasks
      example.run
    end
  end

  after { runs.delete_all }

  it "prints the created run ID and status" do
    expect { task.invoke("2024") }.to output(/Primeira página enfileirada\. sync_run_id=\d+ status=running/).to_stdout
    expect(enqueued_jobs.first.fetch(:args).first.fetch("sync_run_id")).to eq(runs.sole.id)
  end

  it "shows usage and exits nonzero for an invalid year" do
    expect do
      expect { task.invoke("invalid") }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output(/ano de quatro dígitos.*\n.*camara:sync_votings\[ANO\]/).to_stderr
    expect(enqueued_jobs).to be_empty
  end

  it "reports the active run on stderr without enqueuing a duplicate" do
    run = create(:camara_ingestion_sync_run, :running, filters: { "start_date" => "2024-01-01", "end_date" => "2024-12-31" })

    expect do
      expect { task.invoke("2024") }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output(/sync_run_id=#{run.id} status=running/).to_stderr
    expect(enqueued_jobs).to be_empty
  end
end
