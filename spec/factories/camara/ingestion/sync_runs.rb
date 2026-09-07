# frozen_string_literal: true

FactoryBot.define do
  factory :camara_ingestion_sync_run, class: "Camara::Ingestion::SyncRun" do
    resource { "votings" }
    filters do
      {
        "start_date" => "2026-01-01",
        "end_date" => "2026-12-31"
      }
    end

    trait :running do
      status { "running" }
      started_at { 1.minute.ago }
    end

    trait :succeeded do
      status { "succeeded" }
      started_at { 2.minutes.ago }
      finished_at { 1.minute.ago }
      processed_count { 100 }
    end

    trait :failed do
      status { "failed" }
      started_at { 2.minutes.ago }
      finished_at { 1.minute.ago }
      error_class { "RuntimeError" }
      error_message { "upstream request failed" }
    end
  end
end
