# frozen_string_literal: true

class Camara::Legislation::Vote < ApplicationRecord
  self.table_name = "camara_votes"

  belongs_to :voting,
    class_name: "Camara::Legislation::Voting",
    inverse_of: :votes

  validates :deputy_external_id,
    presence: true,
    uniqueness: { scope: :voting_id }
  validates :fetched_at, :raw_payload, presence: true
  validate :raw_payload_is_an_object

  private

  def raw_payload_is_an_object
    errors.add(:raw_payload, "must be a JSON object") unless raw_payload.is_a?(Hash)
  end
end
