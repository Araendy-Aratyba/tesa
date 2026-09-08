# frozen_string_literal: true

class Camara::Legislation::Voting < ApplicationRecord
  self.table_name = "camara_votings"

  has_many :votes,
    class_name: "Camara::Legislation::Vote",
    inverse_of: :voting,
    dependent: :delete_all
  has_many :orientations,
    class_name: "Camara::Legislation::Orientation",
    inverse_of: :voting,
    dependent: :delete_all

  validates :external_id, presence: true, uniqueness: true
  validates :occurred_on, :source_uri, :fetched_at, :raw_payload, presence: true
  validate :raw_payload_is_an_object

  scope :during, ->(period) { where(occurred_on: period) }
  scope :for_body, ->(external_id) { where(body_external_id: external_id) }
  scope :with_known_result, -> { where(approved: [ true, false ]) }

  private

  def raw_payload_is_an_object
    errors.add(:raw_payload, "must be a JSON object") unless raw_payload.is_a?(Hash)
  end
end
