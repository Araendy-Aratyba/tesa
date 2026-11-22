# frozen_string_literal: true

class Camara::Ingestion::SyncVotingsPageJob < ApplicationJob
  queue_as :camara_sync
  self.enqueue_after_transaction_commit = true
  limits_concurrency to: 1, key: ->(arguments) { arguments.fetch(:sync_run_id) }, duration: 15.minutes

  class PageLimitReached < StandardError; end
  class EnqueueError < StandardError; end

  retry_on CongregaPlenum::ConnectionError, CongregaPlenum::RateLimitError, CongregaPlenum::ServerError,
    wait: :polynomially_longer, attempts: 3

  after_discard do |job, error|
    arguments = job.arguments.first
    if arguments.is_a?(Hash) && arguments[:sync_run_id]
      Camara::Ingestion::PublicApi.fail_running!(sync_run_id: arguments[:sync_run_id], error:)
    end
  end

  def perform(sync_run_id:, page:, start_date: nil, end_date: nil)
    raise ArgumentError, "voting page must be a positive integer" unless page.is_a?(Integer) && page.positive?

    result = Camara::Ingestion::PaginateVotings.call(sync_run_id:, page:, start_date:, end_date:)
    return unless result.page

    result.voting_ids.each do |external_id|
      unless Camara::Ingestion::HydrateVotingJob.perform_later(external_id:)
        raise EnqueueError, "could not enqueue voting hydration"
      end
    end
    if result.next_page && !self.class.perform_later(
      sync_run_id:, page: result.next_page, start_date: result.start_date, end_date: result.end_date
    )
      raise EnqueueError, "could not enqueue next voting page"
    end

    raise PageLimitReached, "voting pagination reached its configured page limit" if result.status == :page_limit_reached

    Camara::Ingestion::PublicApi.acknowledge_voting_page!(sync_run_id:, page:)
  end
end
