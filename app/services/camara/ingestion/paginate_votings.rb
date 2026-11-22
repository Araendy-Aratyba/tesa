# frozen_string_literal: true

class Camara::Ingestion::PaginateVotings
  PAGE_SIZE = 100
  DEFAULT_MAX_PAGES = 1_000
  Result = Data.define(:status, :page, :next_page, :import_result)
  class InvalidRequest < ArgumentError; end

  def self.call(sync_run_id:, client: CongregaPlenum::VotingsService)
    new(sync_run_id:, client:).call
  end

  def initialize(sync_run_id:, client:)
    @sync_run_id = sync_run_id
    @client = client
  end

  def call
    if ApplicationRecord.current_transaction.open?
      raise InvalidRequest, "voting pagination must run outside a database transaction"
    end

    run = Camara::Ingestion::PublicApi.configure_voting_pagination!(sync_run_id: @sync_run_id) do |filters, checkpoint|
      configured_filters(filters, checkpoint)
    end
    return result_for(run) if run.pagination_completed_at || run.page.to_i >= run.filters.fetch("max_pages")

    page = run.page.to_i + 1
    result = Camara::Ingestion::ImportVotingsPage.call(sync_run_id: @sync_run_id, page:, client: @client)
    confirmed_run = Camara::Ingestion::PublicApi.fetch(sync_run_id: @sync_run_id)
    result_for(confirmed_run, page:, import_result: result)
  end

  private

  def configured_filters(filters, checkpoint)
    validate_limits!(filters, checkpoint)
    filters = resolve_dates(filters)
    Camara::Ingestion::VotingsDateRange.call(filters)

    # A checkpoint from T06 used the client's defaults before ordering was stored.
    order = checkpoint ? CongregaPlenum::VotingsService::DEFAULT_ORDER : "ASC"
    order_by = checkpoint ? CongregaPlenum::VotingsService::DEFAULT_ORDER_BY : "id"
    filters.merge(
      "order" => filters["order"] || order,
      "order_by" => filters["order_by"] || order_by,
      "max_pages" => filters.fetch("max_pages", DEFAULT_MAX_PAGES),
      "items_per_page" => PAGE_SIZE
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
    if run.pagination_completed_at
      Result.new(status: :complete, page:, next_page: nil, import_result:)
    elsif run.page.to_i >= run.filters.fetch("max_pages")
      Result.new(status: :page_limit_reached, page:, next_page: nil, import_result:)
    else
      Result.new(status: :continue, page:, next_page: run.page.to_i + 1, import_result:)
    end
  end
end
