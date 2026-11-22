# frozen_string_literal: true

module Camara::Representatives::Mappers::Legislature
  def self.call(payload, fetched_at:)
    invalid!("dados") unless payload.is_a?(Hash)

    number = Integer(payload["id"].to_s, 10, exception: false)
    invalid!("id") unless number&.positive? && number.to_s == payload["id"].to_s
    uri = payload["uri"]
    invalid!("uri") unless uri.is_a?(String) && uri.present?
    starts_on = date(payload, "dataInicio")
    ends_on = date(payload, "dataFim")
    invalid!("dataFim") if ends_on < starts_on
    election_year = payload["anoEleicao"]
    unless election_year.nil?
      election_year = Integer(election_year.to_s, 10, exception: false)
      invalid!("anoEleicao") unless election_year&.between?(1000, 9999)
    end

    { external_id: number.to_s, number:, source_uri: uri, starts_on:, ends_on:, election_year:,
      raw_payload: payload, fetched_at: }
  end

  def self.date(payload, field)
    value = payload[field]
    invalid!(field) unless value.is_a?(String) && value.match?(/\A[0-9]{4}-[0-9]{2}-[0-9]{2}\z/)

    Date.iso8601(value)
  rescue Date::Error
    invalid!(field)
  end
  private_class_method :date

  def self.invalid!(field)
    raise Camara::Representatives::Mappers::ContractError.new(resource: :legislature, field:)
  end
  private_class_method :invalid!
end
