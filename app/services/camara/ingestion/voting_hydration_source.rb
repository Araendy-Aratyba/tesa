# frozen_string_literal: true

class Camara::Ingestion::VotingHydrationSource < CongregaPlenum::VotingsService
  def self.api_get(...)
    response = super

    # The gem's collection methods collapse missing or null data into [].
    unless response.is_a?(Hash) && (response["dados"].is_a?(Hash) || response["dados"].is_a?(Array))
      raise CongregaPlenum::APIError, "voting hydration requires an explicit data object or array"
    end

    links = response.fetch("links", [])
    unless links.is_a?(Array) && links.all? { |link| link.is_a?(Hash) && link["rel"] != "next" }
      raise CongregaPlenum::APIError, "voting hydration requires a complete response"
    end

    response
  end
end
