# frozen_string_literal: true

module Camara::Ingestion::PublicApi
  SyncRunSnapshot = Data.define(
    :id,
    :resource,
    :status,
    :filters,
    :page,
    :cursor,
    :processed_count,
    :failed_count,
    :started_at,
    :finished_at,
    :error_class,
    :error_message
  )

  def self.start!(sync_run_id:)
    transition(sync_run_id:) { |sync_run| sync_run.start! }
  end

  def self.record_progress!(sync_run_id:, **progress)
    transition(sync_run_id:) { |sync_run| sync_run.record_progress!(**progress) }
  end

  def self.succeed!(sync_run_id:)
    transition(sync_run_id:) { |sync_run| sync_run.succeed! }
  end

  def self.fail!(sync_run_id:, error:)
    transition(sync_run_id:) { |sync_run| sync_run.fail!(error:) }
  end

  def self.transition(sync_run_id:)
    sync_run = Camara::Ingestion::SyncRun.find(sync_run_id)
    yield sync_run
    snapshot(sync_run)
  end
  private_class_method :transition

  def self.snapshot(sync_run)
    SyncRunSnapshot.new(
      id: sync_run.id,
      resource: immutable_string(sync_run.resource),
      status: immutable_string(sync_run.status),
      filters: deep_frozen_copy(sync_run.filters),
      page: sync_run.page,
      cursor: immutable_string(sync_run.cursor),
      processed_count: sync_run.processed_count,
      failed_count: sync_run.failed_count,
      started_at: sync_run.started_at,
      finished_at: sync_run.finished_at,
      error_class: immutable_string(sync_run.error_class),
      error_message: immutable_string(sync_run.error_message)
    )
  end
  private_class_method :snapshot

  def self.immutable_string(value)
    value&.dup&.freeze
  end
  private_class_method :immutable_string

  def self.deep_frozen_copy(value)
    copy = case value
    when Hash
      value.to_h { |key, nested_value| [ deep_frozen_copy(key), deep_frozen_copy(nested_value) ] }
    when Array
      value.map { |nested_value| deep_frozen_copy(nested_value) }
    when String
      value.dup
    else
      value
    end

    copy.freeze
  end
  private_class_method :deep_frozen_copy
end
