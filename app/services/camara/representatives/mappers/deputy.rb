# frozen_string_literal: true

module Camara::Representatives::Mappers::Deputy
  def self.detail(payload, fetched_at:)
    identity = Camara::Representatives::Mappers::Identity.call(payload, resource: :deputy)
    status = payload["ultimoStatus"]
    invalid!("ultimoStatus") unless status.is_a?(Hash) && status.present?
    if !status["id"].nil? && status["id"].to_s != identity.fetch(:external_id)
      invalid!("ultimoStatus.id")
    end

    legislature = status["idLegislatura"]
    if !legislature.nil? && !legislature.to_s.match?(/\A[1-9][0-9]*\z/)
      invalid!("ultimoStatus.idLegislatura")
    end

    {
      **identity, civil_name: text(payload, "nomeCivil"), electoral_name: text(status, "nomeEleitoral"),
      state_acronym: text(status, "siglaUf"), situation: text(status, "situacao"), party_acronym: text(status, "siglaPartido"),
      party_source_uri: text(status, "uriPartido"), current_legislature_external_id: legislature&.to_s,
      raw_payload: payload, fetched_at:
    }
  end

  def self.text(payload, field)
    value = payload[field]
    invalid!(field) unless value.nil? || value.is_a?(String)

    value.presence
  end
  private_class_method :text

  def self.invalid!(field)
    raise Camara::Representatives::Mappers::ContractError.new(resource: :deputy, field:)
  end
  private_class_method :invalid!
end
