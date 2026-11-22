# frozen_string_literal: true

class Camara::Ingestion::SyncRepresentativeCatalog
  MAX_PAGES = 1_000
  Result = Data.define(:next_page)
  class PageLimitReached < StandardError; end

  def self.call(...)
    new(...).call
  end

  def initialize(sync_run_id:, page:)
    @sync_run_id = sync_run_id
    @page = page
  end

  def call
    if ApplicationRecord.current_transaction.open?
      raise ArgumentError, "representative sync must run outside a database transaction"
    end

    run = Camara::Ingestion::SyncRun.find(@sync_run_id)
    return Result.new(next_page: nil) unless run.running?

    catalogue = Camara::Ingestion::RepresentativeCatalogs.fetch(run.resource)
    case run.filters.fetch("mode")
    when "catalog"
      sync_page(run, catalogue)
    when "detail"
      sync_detail(run, catalogue)
    else
      raise ArgumentError, "unknown representative sync mode"
    end
  end

  private

  def sync_page(run, catalogue)
    raise ArgumentError, "page must be a positive integer" unless @page.is_a?(Integer) && @page.positive?

    checkpoint = run.page.to_i
    if @page <= checkpoint
      return Result.new(next_page: (@page + 1 if @page == checkpoint && @page < MAX_PAGES))
    end
    raise ArgumentError, "requested page would skip the checkpoint" unless @page == checkpoint + 1

    scope = catalogue.legislature_scoped ? { legislature_id: Integer(run.filters.fetch("legislature_id"), 10) } : {}
    page = catalogue.source.fetch_page(page: @page, **scope)
    result = import(catalogue, page.records, **scope)
    run.confirm_catalog_page!(page: @page, record_count: result.record_count, complete: page.next_page.nil?)
    raise PageLimitReached, "representative catalogue reached its page limit" if page.next_page && @page == MAX_PAGES

    Result.new(next_page: page.next_page)
  end

  def sync_detail(run, catalogue)
    raise ArgumentError, "detail sync does not take a page" if @page

    external_id = run.filters.fetch("external_id")
    payload = catalogue.source.fetch_by_id(Integer(external_id, 10))
    result = import(catalogue, [ payload ], expected_id: external_id)
    run.complete_catalog_detail!(record_count: result.record_count)
    Result.new(next_page: nil)
  end

  def import(catalogue, payloads, expected_id: nil, **scope)
    Camara::Representatives::PublicApi.public_send(catalogue.import_method,
      payloads:, fetched_at: Time.current, expected_id:, **scope)
  end
end
