# frozen_string_literal: true

class Camara::Ingestion::SyncRun < ApplicationRecord
  self.table_name = "camara_sync_runs"

  has_many :voting_hydration_failures,
    class_name: "Camara::Ingestion::VotingHydrationFailure", inverse_of: :sync_run

  FILTER_SCHEMAS = {
    "votings" => %w[start_date end_date],
    "legislatures" => %w[mode],
    "parties" => %w[mode],
    "deputies" => %w[mode]
  }.freeze
  MAX_ERROR_CLASS_LENGTH = 255
  MAX_ERROR_MESSAGE_LENGTH = 1_000
  UNSET_PROGRESS_VALUE = Object.new.freeze
  SENSITIVE_PARAMETER_PATTERN = %r~
    (?<prefix>\b(?:password|secret|token|access[_-]?token|api[_-]?key)\b["']?\s*(?::|=>|=)\s*)
    (?:"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|[^\s&,;}]+)
  ~ix
  AUTHORIZATION_PATTERN = %r~
    (?<prefix>\bauthorization\b["']?\s*(?::|=>|=)\s*)
    (?:"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|(?:bearer\s+)?[^\s&,;}]+)
  ~ix
  BEARER_PATTERN = /\bbearer\s+([^\s&,;]+)/i

  class InvalidTransition < StandardError; end
  class InvalidProgress < StandardError; end

  enum :status, {
    pending: "pending",
    running: "running",
    succeeded: "succeeded",
    failed: "failed"
  }, validate: true

  validates :resource, presence: true, inclusion: { in: FILTER_SCHEMAS.keys }
  validates :filters, presence: true
  validates :page, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :processed_count, :failed_count,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :cursor, :error_class, length: { maximum: MAX_ERROR_CLASS_LENGTH }, allow_nil: true
  validates :error_message, length: { maximum: MAX_ERROR_MESSAGE_LENGTH }, allow_nil: true
  validate :filters_are_an_object
  validate :filters_match_resource_schema
  validate :state_attributes_are_consistent
  validate :finished_at_is_not_before_started_at

  def start!
    with_lock do
      ensure_status!(:pending)
      update!(status: :running, started_at: Time.current)
    end

    self
  end

  def record_progress!(page: UNSET_PROGRESS_VALUE, cursor: UNSET_PROGRESS_VALUE,
                       processed_count: UNSET_PROGRESS_VALUE, failed_count: UNSET_PROGRESS_VALUE)
    progress = compact_progress(page:, cursor:, processed_count:, failed_count:)
    raise ArgumentError, "at least one progress value is required" if progress.empty?

    with_lock do
      ensure_status!(:running)
      ensure_progress_does_not_regress!(progress)
      update!(progress)
    end

    self
  end

  def succeed!
    with_lock do
      ensure_status!(:running)
      update!(status: :succeeded, finished_at: Time.current)
    end

    self
  end

  def configure_voting_pagination!
    with_lock do
      ensure_status!(:running)
      update!(filters: yield(filters, page))
    end

    self
  end

  def record_imported_page!(page:, persisted_count:, exhausted: false, voting_ids: nil)
    unless page.is_a?(Integer) && page.positive? && persisted_count.is_a?(Integer) && persisted_count >= 0
      raise InvalidProgress, "expected a positive page and a nonnegative persisted count"
    end

    with_lock do
      ensure_status!(:running)
      checkpoint = self.page || 0
      raise InvalidProgress, "cannot skip an imported page" if page > checkpoint + 1

      if page > checkpoint
        raise InvalidProgress, "voting pagination is already complete" if pagination_completed_at

        update!(page:, processed_count: processed_count + persisted_count,
          pagination_completed_at: (Time.current if exhausted), pending_voting_ids: voting_ids)
      end
    end

    self
  end

  def confirm_catalog_page!(page:, record_count:, complete:)
    with_lock do
      checkpoint = self.page.to_i
      next unless running? && page > checkpoint

      raise InvalidProgress, "cannot skip a catalogue page" unless page == checkpoint + 1

      progress = { page:, processed_count: processed_count + record_count }
      if complete
        now = Time.current
        progress.merge!(status: :succeeded, finished_at: now, pagination_completed_at: now)
      end
      update!(progress)
    end
  end

  def complete_catalog_detail!(record_count:)
    with_lock do
      next unless running?

      update!(status: :succeeded, finished_at: Time.current, processed_count: record_count)
    end
  end

  def acknowledge_voting_page!(page:)
    with_lock do
      update!(pending_voting_ids: nil) if self.page == page && pending_voting_ids
    end

    self
  end

  def fail!(error:, only_if_running: false)
    raise ArgumentError, "error must respond to #message" unless error.respond_to?(:message)

    with_lock do
      next if only_if_running && !running?

      ensure_status!(:running)
      update!(
        status: :failed,
        finished_at: Time.current,
        error_class: sanitized_error_class(error),
        error_message: sanitized_error_message(error)
      )
    end

    self
  end

  private

  def compact_progress(page:, cursor:, processed_count:, failed_count:)
    {
      page:,
      cursor:,
      processed_count:,
      failed_count:
    }.reject { |_attribute, value| value.equal?(UNSET_PROGRESS_VALUE) }
  end

  def ensure_status!(expected_status)
    return if status == expected_status.to_s

    raise InvalidTransition, "cannot transition sync run from #{status}"
  end

  def ensure_progress_does_not_regress!(progress)
    %i[page processed_count failed_count].each do |attribute|
      next unless progress.key?(attribute)

      current_value = public_send(attribute)
      next if current_value.nil? || progress.fetch(attribute).to_i >= current_value

      raise InvalidProgress, "#{attribute} cannot move backwards"
    end
  end

  def sanitized_error_class(error)
    (error.class.name.presence || error.class.to_s).first(MAX_ERROR_CLASS_LENGTH)
  end

  def sanitized_error_message(error)
    message = error.message.to_s.presence || sanitized_error_class(error)
    message = message.gsub(AUTHORIZATION_PATTERN, '\\k<prefix>[FILTERED]')
    message = message.gsub(SENSITIVE_PARAMETER_PATTERN, '\\k<prefix>[FILTERED]')
    message.gsub(BEARER_PATTERN, "Bearer [FILTERED]").first(MAX_ERROR_MESSAGE_LENGTH)
  end

  def filters_are_an_object
    errors.add(:filters, "must be a JSON object") unless filters.is_a?(Hash)
  end

  def filters_match_resource_schema
    return unless filters.is_a?(Hash)

    required_filters = FILTER_SCHEMAS[resource]
    return unless required_filters

    normalized_filters = filters.stringify_keys
    missing_filters = required_filters.reject { |filter| normalized_filters[filter].present? }
    return if missing_filters.empty?
    return if resource == "votings" && normalized_filters["mode"] == "incremental" && missing_filters == required_filters

    errors.add(:filters, "must include #{missing_filters.join(', ')} for #{resource}")
  end

  def state_attributes_are_consistent
    case status
    when "pending"
      require_blank_state_attributes(:started_at, :finished_at, :error_class, :error_message)
    when "running"
      require_present_state_attributes(:started_at)
      require_blank_state_attributes(:finished_at, :error_class, :error_message)
    when "succeeded"
      require_present_state_attributes(:started_at, :finished_at)
      require_blank_state_attributes(:error_class, :error_message)
    when "failed"
      require_present_state_attributes(:started_at, :finished_at, :error_class, :error_message)
    end
  end

  def require_present_state_attributes(*attributes)
    attributes.each do |attribute|
      errors.add(attribute, "must be present when status is #{status}") if public_send(attribute).blank?
    end
  end

  def require_blank_state_attributes(*attributes)
    attributes.each do |attribute|
      errors.add(attribute, "must be blank when status is #{status}") if public_send(attribute).present?
    end
  end

  def finished_at_is_not_before_started_at
    return if started_at.blank? || finished_at.blank? || finished_at >= started_at

    errors.add(:finished_at, "cannot be before started_at")
  end
end
