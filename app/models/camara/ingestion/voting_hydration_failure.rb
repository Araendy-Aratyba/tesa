# frozen_string_literal: true

class Camara::Ingestion::VotingHydrationFailure < ApplicationRecord
  self.table_name = "camara_voting_hydration_failures"

  belongs_to :sync_run, class_name: "Camara::Ingestion::SyncRun", inverse_of: :voting_hydration_failures

  validates :voting_external_id, :job_id, :error_class, presence: true
  validates :attempts, numericality: { only_integer: true, greater_than: 0 }
end
