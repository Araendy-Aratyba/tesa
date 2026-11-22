# frozen_string_literal: true

class Camara::Representatives::Deputy < ApplicationRecord
  self.table_name = "camara_deputies"

  has_many :listing_observations, class_name: "Camara::Representatives::DeputyListingObservation", inverse_of: :deputy

  validates :external_id, :source_uri, presence: true
  validate { errors.add(:raw_payload, "must be a JSON object") if !raw_payload.nil? && !raw_payload.is_a?(Hash) }

  scope :with_electoral_name, ->(name) { where("lower(electoral_name) = lower(?)", name) }
  scope :from_state, ->(state_acronym) { where(state_acronym:) }
  scope :with_situation, ->(situation) { where(situation:) }
end
