# frozen_string_literal: true

class Camara::Ingestion::SyncRepresentativeCatalogJob < ApplicationJob
  queue_as { arguments.first[:page] ? :camara_sync : :camara_hydration }
  self.enqueue_after_transaction_commit = true
  limits_concurrency to: 1, key: ->(arguments) { arguments.fetch(:sync_run_id) }, duration: 15.minutes

  retry_on CongregaPlenum::ConnectionError, CongregaPlenum::RateLimitError, CongregaPlenum::ServerError,
    wait: :polynomially_longer, attempts: 3

  after_discard do |job, error|
    arguments = job.arguments.first
    if arguments.is_a?(Hash) && arguments[:sync_run_id]
      Camara::Ingestion::PublicApi.fail_running!(sync_run_id: arguments.fetch(:sync_run_id), error:)
    end
  end

  def perform(sync_run_id:, page:)
    result = Camara::Ingestion::SyncRepresentativeCatalog.call(sync_run_id:, page:)
    if result.next_page && !self.class.perform_later(sync_run_id:, page: result.next_page)
      raise Camara::Ingestion::StartRepresentativeSync::EnqueueError, "queue rejected the next representative page"
    end
  end
end
