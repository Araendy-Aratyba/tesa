# frozen_string_literal: true

class Camara::Ingestion::StartRepresentativeSync
  Result = Data.define(:sync_run_id, :status, :error)
  class EnqueueError < StandardError; end

  def self.call(...)
    new(...).call
  end

  def initialize(resource:, external_id: nil)
    @resource = resource.to_s
    Camara::Ingestion::RepresentativeCatalogs.fetch(@resource)
    @filters = if external_id.nil?
      { "mode" => "catalog" }
    else
      unless external_id.to_s.match?(/\A[1-9][0-9]*\z/)
        raise ArgumentError, "expected a positive external ID"
      end

      { "mode" => "detail", "external_id" => external_id.to_s }
    end
  end

  def call
    if ApplicationRecord.current_transaction.open?
      raise ArgumentError, "representative sync must start outside a database transaction"
    end

    run, created = claim_run
    return Result.new(sync_run_id: run.id, status: run.status.to_sym, error: :already_active) unless created

    enqueue(run)
  end

  private

  def claim_run
    model = Camara::Ingestion::SyncRun
    model.with_connection do |connection|
      connection.transaction do
        key = [ @resource, *@filters.values ].join("/")
        connection.execute(model.sanitize_sql_array([ "SELECT pg_advisory_xact_lock(hashtext('camara_catalogue'), hashtext(?))", key ]))
        active = model.where(resource: @resource, filters: @filters, status: %i[pending running]).order(:id).first
        next [ active, false ] if active

        run = model.create!(resource: @resource, filters: @filters)
        [ run.start!, true ]
      end
    end
  end

  def enqueue(run)
    page = 1 if @filters.fetch("mode") == "catalog"
    job = Camara::Ingestion::SyncRepresentativeCatalogJob.new(sync_run_id: run.id, page:)
    raise(job.enqueue_error || EnqueueError.new("queue rejected representative sync")) unless job.enqueue

    Result.new(sync_run_id: run.id, status: :running, error: nil)
  rescue EnqueueError, ActiveJob::EnqueueError, SolidQueue::Job::EnqueueError => error
    run.fail!(error:)
    Result.new(sync_run_id: run.id, status: :failed, error: :enqueue_failed)
  end
end
