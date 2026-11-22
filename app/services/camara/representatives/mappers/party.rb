# frozen_string_literal: true

module Camara::Representatives::Mappers::Party
  def self.call(payload, fetched_at:, detail: false)
    identity = Camara::Representatives::Mappers::Identity.call(payload, resource: :party)
    attributes = { **identity, acronym: required_text(payload, "sigla"), name: required_text(payload, "nome"),
      raw_payload: payload, fetched_at: }
    return attributes unless detail

    status = payload["status"]
    invalid!("status") unless status.nil? || status.is_a?(Hash)
    situation = status&.fetch("situacao", nil)
    invalid!("status.situacao") unless situation.nil? || situation.is_a?(String)

    attributes.merge(situation:, detail_raw_payload: payload, detail_fetched_at: fetched_at)
  end

  def self.required_text(payload, field)
    text = payload[field]
    invalid!(field) unless text.is_a?(String) && text.present?

    text
  end
  private_class_method :required_text

  def self.invalid!(field)
    raise Camara::Representatives::Mappers::ContractError.new(resource: :party, field:)
  end
  private_class_method :invalid!
end
