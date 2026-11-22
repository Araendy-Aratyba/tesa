# frozen_string_literal: true

module Camara::Ingestion::RecordVotingHydrationFailure
  def self.call(sync_run_id:, external_id:, job_id:, attempts:, error:)
    sync_run = Camara::Ingestion::SyncRun.find_by(id: sync_run_id)
    return unless sync_run

    source_error = error.is_a?(Camara::Ingestion::HydrateVoting::FetchError) ? error.cause : error

    sync_run.with_lock do
      failure = sync_run.voting_hydration_failures.find_or_initialize_by(voting_external_id: external_id)
      first_failure = failure.new_record?
      failure.update!(job_id:, attempts:, error_class: (source_error || error).class.name)
      sync_run.update!(failed_count: sync_run.failed_count + 1) if first_failure
    end
  end
end
