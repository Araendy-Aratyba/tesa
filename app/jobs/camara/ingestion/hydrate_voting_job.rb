# frozen_string_literal: true

# Keep already serialized jobs executable across the rollout.
class Camara::Ingestion::HydrateVotingJob < Camara::Legislation::HydrateVotingJob
  def perform(external_id:, sync_run_id: nil)
    super(external_id:, sync_run_id:)
  end
end
