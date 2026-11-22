# frozen_string_literal: true

class Camara::Representatives::Legislature < ApplicationRecord
  self.table_name = "camara_legislatures"

  validates :external_id, :source_uri, :starts_on, :ends_on, :fetched_at, presence: true
  validates :number, numericality: { only_integer: true, greater_than: 0 }
  validates :ends_on, comparison: { greater_than_or_equal_to: :starts_on }, if: :starts_on?, allow_nil: true
  validate { errors.add(:raw_payload, "must be a JSON object") unless raw_payload.is_a?(Hash) }

  scope :covering, ->(date) { where("starts_on <= :date AND ends_on >= :date", date:) }
end
