# frozen_string_literal: true

class Camara::Representatives::DeputyListingObservation < ApplicationRecord
  self.table_name = "camara_deputy_listing_observations"

  belongs_to :deputy, class_name: "Camara::Representatives::Deputy", inverse_of: :listing_observations

  validates :legislature_external_id, :payload_fingerprint, :first_seen_at, :last_seen_at, presence: true
  validates :last_seen_at, comparison: { greater_than_or_equal_to: :first_seen_at }, if: :first_seen_at?, allow_nil: true
  validate { errors.add(:raw_payload, "must be a JSON object") unless raw_payload.is_a?(Hash) }
end
