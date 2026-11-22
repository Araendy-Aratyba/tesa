# frozen_string_literal: true

module Camara::Ingestion::VotingsDateRange
  class InvalidRange < ArgumentError; end

  def self.call(filters)
    start_date = Date.iso8601(filters.fetch("start_date"))
    end_date = Date.iso8601(filters.fetch("end_date"))
    unless start_date <= end_date && start_date.year == end_date.year
      raise InvalidRange, "voting dates must be ordered and within one calendar year"
    end

    [ start_date, end_date ]
  rescue Date::Error, KeyError, TypeError
    raise InvalidRange, "start_date and end_date must be ISO 8601 dates", cause: nil
  end
end
