# frozen_string_literal: true

module Camara::Representatives::Mappers::Identity
  def self.call(payload, resource:)
    invalid!(resource, "dados") unless payload.is_a?(Hash)

    id = payload["id"]
    unless (id.is_a?(Integer) || id.is_a?(String)) && id.to_s.match?(/\A[1-9][0-9]*\z/)
      invalid!(resource, "id")
    end
    uri = payload["uri"]
    invalid!(resource, "uri") unless uri.is_a?(String) && uri.present?

    { external_id: id.to_s, source_uri: uri }
  end

  def self.invalid!(resource, field)
    raise Camara::Representatives::Mappers::ContractError.new(resource:, field:)
  end
  private_class_method :invalid!
end
