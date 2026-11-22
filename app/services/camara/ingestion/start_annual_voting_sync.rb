# frozen_string_literal: true

class Camara::Ingestion::StartAnnualVotingSync
  FIRST_YEAR = 1935
  Result = Data.define(:sync_run_id, :status, :error)

  class EnqueueError < StandardError; end

  def self.call(...)
    new(...).call
  end

  def self.supported_years
    FIRST_YEAR..Date.current.year
  end

  def initialize(year:)
    @year = year.to_i if year.is_a?(String) && year.match?(/\A[0-9]{4}\z/)
  end

  def call
    unless self.class.supported_years.cover?(@year)
      return Result.new(sync_run_id: nil, status: nil, error: :invalid_year)
    end
    if ApplicationRecord.current_transaction.open?
      raise ArgumentError, "annual voting sync must start outside a database transaction"
    end

    filters = { "start_date" => "#{@year}-01-01", "end_date" => "#{@year}-12-31" }
    run, created = claim_run(filters)
    return Result.new(sync_run_id: run.id, status: run.status.to_sym, error: :already_active) unless created

    enqueue_first_page(run, filters)
  end

  private

  def claim_run(filters)
    Camara::Ingestion::SyncRun.with_connection do |connection|
      connection.transaction do
        # Serialize starts for the same year, including when no row exists to lock yet.
        connection.execute(Camara::Ingestion::SyncRun.sanitize_sql_array([
          "SELECT pg_advisory_xact_lock(hashtext('camara_annual_voting_sync'), ?)", @year
        ]))
        active_run = Camara::Ingestion::SyncRun.where(resource: "votings", status: %i[pending running])
          .where("filters @> ?::jsonb", filters.to_json).order(:id).first

        if active_run
          [ active_run, false ]
        else
          run = Camara::Ingestion::SyncRun.create!(resource: "votings", filters:)
          [ run.start!, true ]
        end
      end
    end
  end

  def enqueue_first_page(run, filters)
    job = Camara::Ingestion::SyncVotingsPageJob.new(
      sync_run_id: run.id, page: 1, **filters.symbolize_keys
    )
    unless job.enqueue
      raise job.enqueue_error || EnqueueError.new("queue rejected the first voting page")
    end

    Result.new(sync_run_id: run.id, status: :running, error: nil)
  rescue EnqueueError, ActiveJob::EnqueueError, SolidQueue::Job::EnqueueError => error
    run.fail!(error:)
    Result.new(sync_run_id: run.id, status: :failed, error: :enqueue_failed)
  end
end
