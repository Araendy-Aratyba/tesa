# frozen_string_literal: true

require "date"

class Camara::Legislation::Mappers::Payload
  ISO_DATE = /\A\d{4}-\d{2}-\d{2}\z/
  ISO_TIMESTAMP = /
    \A\d{4}-\d{2}-\d{2}T(?:[01]\d|2[0-3]):[0-5]\d:[0-5]\d(?:\.\d+)?
    (?<offset>Z|[+-](?:[01]\d|2[0-3])(?::?[0-5]\d)?)?\z
  /x

  attr_reader :fetched_at

  def initialize(payload, resource:, fetched_at:)
    @resource = resource
    invalid!("payload", "expected a JSON object") unless payload.is_a?(Hash)
    @payload = payload

    invalid!("fetched_at", "expected a Time") unless fetched_at.is_a?(Time)
    @fetched_at = fetched_at.getutc
  end

  def [](field)
    @payload[field]
  end

  def text(value)
    value if value.is_a?(String) && !value.strip.empty?
  end

  def identifier(value)
    value.is_a?(Integer) ? value.to_s : text(value)
  end

  def required(field, value, expectation:)
    value || invalid!(field, expectation)
  end

  def date(field)
    value = self[field]
    invalid!(field, "expected an ISO 8601 date") unless value.is_a?(String) && ISO_DATE.match?(value)

    Date.iso8601(value)
  rescue Date::Error
    invalid!(field, "expected a valid calendar date")
  end

  def instant(field)
    value = self[field]
    return if value.nil? || (value.is_a?(String) && value.strip.empty?)

    match = ISO_TIMESTAMP.match(value) if value.is_a?(String)
    invalid!(field, "expected an ISO 8601 timestamp") unless match

    time = DateTime.iso8601(value).to_time
    return time.utc if match[:offset]

    Time.zone.tzinfo.local_to_utc(time, nil).utc
  rescue Date::Error
    invalid!(field, "expected a valid calendar timestamp")
  rescue TZInfo::AmbiguousTime, TZInfo::PeriodNotFound
    invalid!(field, "expected an unambiguous timestamp in the application time zone")
  end

  def invalid!(field, expectation)
    raise Camara::Legislation::Mappers::ContractError.new(resource: @resource, field:, expectation:), cause: nil
  end
end
