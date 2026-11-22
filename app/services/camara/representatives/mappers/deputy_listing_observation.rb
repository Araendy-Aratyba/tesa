# frozen_string_literal: true

require "digest"

module Camara::Representatives::Mappers::DeputyListingObservation
  def self.call(payload, legislature_id:, fetched_at:)
    identity = Camara::Representatives::Mappers::Identity.call(payload, resource: :deputy)
    fingerprint = Digest::SHA256.hexdigest(JSON.generate(canonical(payload)))
    [ identity, { legislature_external_id: legislature_id.to_s, payload_fingerprint: fingerprint,
      raw_payload: payload, first_seen_at: fetched_at, last_seen_at: fetched_at } ]
  end

  def self.canonical(value)
    case value
    when Hash then value.sort.to_h.transform_values { |child| canonical(child) }
    when Array then value.map { |child| canonical(child) }
    else value
    end
  end
  private_class_method :canonical
end
