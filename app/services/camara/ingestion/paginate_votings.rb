# frozen_string_literal: true

class Camara::Ingestion::PaginateVotings
  PAGE_SIZE = 100
  DEFAULT_MAX_PAGES = 1_000
  Result = Data.define(:status, :page, :next_page, :import_result, :voting_ids, :start_date, :end_date)
  class InvalidRequest < ArgumentError; end

  def self.call(...)
    new(...).call
  end

  def initialize(sync_run_id:, client: CongregaPlenum::VotingsService, page: nil, start_date: nil, end_date: nil)
    @sync_run_id = sync_run_id
    @client = client
    @requested_page = page
    @requested_dates = [ start_date, end_date ]
  end

  def call
    if ApplicationRecord.current_transaction.open?
      raise InvalidRequest, "voting pagination must run outside a database transaction"
    end

    if @requested_page && Camara::Ingestion::PublicApi.fetch(sync_run_id: @sync_run_id).status != "running"
      return skipped
    end

    run = Camara::Ingestion::PublicApi.configure_voting_pagination!(sync_run_id: @sync_run_id) do |filters, checkpoint|
      configured_filters(filters, checkpoint)
    end
    if @requested_page && @requested_page <= run.page.to_i
      return skipped unless @requested_page == run.page && run.pending_voting_ids

      return result_for(run, page: @requested_page)
    end
    return result_for(run) if run.pagination_completed_at || run.page.to_i >= run.filters.fetch("max_pages")

    page = run.page.to_i + 1
    if @requested_page && @requested_page != page
      raise InvalidRequest, "requested voting page would skip the checkpoint"
    end

    result = Camara::Ingestion::ImportVotingsPage.call(
      sync_run_id: @sync_run_id, page:, client: @client, retain_voting_ids: !@requested_page.nil?
    )
    confirmed_run = Camara::Ingestion::PublicApi.fetch(sync_run_id: @sync_run_id)
    return skipped if @requested_page && (confirmed_run.page != page || !confirmed_run.pending_voting_ids)

    result_for(confirmed_run, page:, import_result: result)
  end

  private

  def configured_filters(filters, checkpoint)
    validate_limits!(filters, checkpoint)
    filters = resolve_dates(filters)
    dates = Camara::Ingestion::VotingsDateRange.call(filters).map(&:iso8601)
    if @requested_dates.any? && @requested_dates != dates
      raise InvalidRequest, "voting page dates must match the sync run"
    end

    # A checkpoint from T06 used the client's defaults before ordering was stored.
    order = checkpoint ? CongregaPlenum::VotingsService::DEFAULT_ORDER : "ASC"
    order_by = checkpoint ? CongregaPlenum::VotingsService::DEFAULT_ORDER_BY : "id"
    filters.merge(
      "order" => filters["order"] || order,
      "order_by" => filters["order_by"] || order_by,
      "max_pages" => filters.fetch("max_pages", DEFAULT_MAX_PAGES),
      "items_per_page" => PAGE_SIZE,
      "start_date" => dates.first,
      "end_date" => dates.last
    )
  end

  def validate_limits!(filters, checkpoint)
    unless filters.fetch("items_per_page", PAGE_SIZE).eql?(PAGE_SIZE)
      raise InvalidRequest, "resumable voting pagination requires #{PAGE_SIZE} items per page"
    end

    max_pages = filters.fetch("max_pages", DEFAULT_MAX_PAGES)
    unless max_pages.is_a?(Integer) && max_pages.positive?
      raise InvalidRequest, "max_pages must be a positive integer"
    end

    ordering = filters.values_at("order", "order_by")
    legacy_order = [ CongregaPlenum::VotingsService::DEFAULT_ORDER, CongregaPlenum::VotingsService::DEFAULT_ORDER_BY ]
    unless ordering.all?(&:nil?) || ordering == [ "ASC", "id" ] || (checkpoint && ordering == legacy_order)
      raise InvalidRequest, "unsupported voting pagination order"
    end
  end

  def resolve_dates(filters)
    return filters unless filters["mode"] == "incremental" && filters.values_at("start_date", "end_date").all?(&:blank?)

    today = Date.current
    start_date = [ today - 29, today.beginning_of_year ].max
    filters.merge("start_date" => start_date.iso8601, "end_date" => today.iso8601)
  end

  def result_for(run, page: nil, import_result: nil)
    status, next_page = if run.pagination_completed_at
      [ :complete, nil ]
    elsif run.page.to_i >= run.filters.fetch("max_pages")
      [ :page_limit_reached, nil ]
    else
      [ :continue, run.page.to_i + 1 ]
    end
    Result.new(status:, page:, next_page:, import_result:, voting_ids: run.pending_voting_ids,
      start_date: run.filters.fetch("start_date"), end_date: run.filters.fetch("end_date"))
  end

  def skipped
    Result.new(status: :skipped, page: nil, next_page: nil, import_result: nil, voting_ids: nil,
      start_date: nil, end_date: nil)
  end
end
