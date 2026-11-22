# frozen_string_literal: true

class Camara::Legislation::HydrateVotingJob < ApplicationJob
  queue_as :camara_hydration
  self.enqueue_after_transaction_commit = true
  limits_concurrency to: 1, key: ->(arguments) { arguments.fetch(:external_id) },
    group: "camara_voting_hydration", duration: 15.minutes

  # Active Job also matches the CongregaPlenum cause of a hydration FetchError.
  retry_on CongregaPlenum::ConnectionError, CongregaPlenum::RateLimitError, CongregaPlenum::ServerError,
    wait: :polynomially_longer, attempts: 3

  after_discard do |job, error|
    arguments = job.arguments.first
    if arguments.is_a?(Hash) && arguments[:sync_run_id] && arguments[:external_id].present?
      Camara::Ingestion::PublicApi.record_voting_hydration_failure!(
        sync_run_id: arguments.fetch(:sync_run_id), external_id: arguments.fetch(:external_id),
        job_id: job.job_id, attempts: job.executions, error:
      )
    end
  end

  def perform(external_id:, sync_run_id:)
    Camara::Ingestion::PublicApi.hydrate_voting(external_id:)
  end
end
