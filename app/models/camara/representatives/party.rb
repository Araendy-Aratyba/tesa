# frozen_string_literal: true

class Camara::Representatives::Party < ApplicationRecord
  self.table_name = "camara_parties"

  validates :external_id, :source_uri, :acronym, :name, :fetched_at, presence: true
  validate :payloads_are_objects

  private

  def payloads_are_objects
    errors.add(:raw_payload, "must be a JSON object") unless raw_payload.is_a?(Hash)
    if !detail_raw_payload.nil? && !detail_raw_payload.is_a?(Hash)
      errors.add(:detail_raw_payload, "must be a JSON object")
    end
  end
end
