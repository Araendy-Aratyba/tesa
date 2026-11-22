# frozen_string_literal: true

class Camara::Ingestion::HydrateVotingJob < ApplicationJob
  queue_as :camara_hydration
  self.enqueue_after_transaction_commit = true

  def perform(external_id:)
    Camara::Ingestion::HydrateVoting.call(external_id:)
  end
end
