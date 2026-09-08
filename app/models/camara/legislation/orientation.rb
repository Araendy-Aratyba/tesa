# frozen_string_literal: true

class Camara::Legislation::Orientation < ApplicationRecord
  self.table_name = "camara_orientations"

  belongs_to :voting,
    class_name: "Camara::Legislation::Voting",
    inverse_of: :orientations

  validates :group_key,
    presence: true,
    uniqueness: { scope: :voting_id }
  validates :fetched_at, :raw_payload, presence: true
  validate :raw_payload_is_an_object

  private

  def raw_payload_is_an_object
    errors.add(:raw_payload, "must be a JSON object") unless raw_payload.is_a?(Hash)
  end
end
