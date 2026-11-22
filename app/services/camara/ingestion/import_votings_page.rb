# frozen_string_literal: true

class Camara::Ingestion::ImportVotingsPage
  Result = Data.define(:received_count, :persisted_count, :voting_ids, :next_page)
  class InvalidRequest < ArgumentError; end
  class InvalidResponse < StandardError; end

  def self.call(...)
    new(...).call
  end

  def initialize(sync_run_id:, page:, items_per_page: nil, client: CongregaPlenum::VotingsService, retain_voting_ids: false)
    @sync_run_id = sync_run_id
    @page = page
    @items_per_page = items_per_page
    @client = client
    @retain_voting_ids = retain_voting_ids
  end

  def call
    if ApplicationRecord.current_transaction.open?
      raise InvalidRequest, "voting import must run outside a database transaction"
    end

    sync_run = Camara::Ingestion::SyncRun.find(@sync_run_id)
    validate_request!(sync_run)
    items_per_page = page_size(sync_run.filters)
    start_date, end_date = date_range(sync_run.filters)

    ordering = sync_run.filters.slice("order", "order_by").symbolize_keys
    payloads = @client.fetch_list(page: @page, items_per_page:, start_date:, end_date:, **ordering)
    unless payloads.is_a?(Array) && payloads.length <= items_per_page
      raise InvalidResponse, "expected a voting page with at most #{items_per_page} records"
    end

    voting_ids = Camara::Legislation::PublicApi.import_votings_page(payloads:, fetched_at: Time.current)
    exhausted = payloads.length < items_per_page
    Camara::Ingestion::PublicApi.record_imported_page!(
      sync_run_id: @sync_run_id, page: @page, persisted_count: voting_ids.length, exhausted:,
      voting_ids: (voting_ids if @retain_voting_ids)
    )

    Result.new(
      received_count: payloads.length,
      persisted_count: voting_ids.length,
      voting_ids:,
      next_page: (@page + 1 unless exhausted)
    )
  end

  private

  def validate_request!(sync_run)
    unless sync_run.running? && sync_run.resource == "votings"
      raise InvalidRequest, "a running votings sync is required"
    end
    unless @page.is_a?(Integer) && @page.between?(1, (sync_run.page || 0) + 1)
      raise InvalidRequest, "page must be positive and cannot skip the checkpoint"
    end
    if sync_run.pagination_completed_at && @page > sync_run.page
      raise InvalidRequest, "voting pagination is already complete"
    end
  end

  def page_size(filters)
    maximum = CongregaPlenum::VotingsService::ITEMS_PER_PAGE
    size = filters.fetch("items_per_page", maximum)
    unless size.is_a?(Integer) && size.between?(1, maximum)
      raise InvalidRequest, "invalid number of items per page"
    end
    unless @items_per_page.nil? || @items_per_page.eql?(size)
      raise InvalidRequest, "items per page must match the sync filters"
    end

    size
  end

  def date_range(filters)
    Camara::Ingestion::VotingsDateRange.call(filters)
  rescue Camara::Ingestion::VotingsDateRange::InvalidRange => error
    raise InvalidRequest, error.message, cause: nil
  end
end
