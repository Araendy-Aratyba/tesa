# frozen_string_literal: true

class Camara::Legislation::ImportVotingsPage
  def self.call(payloads:, fetched_at:)
    attributes = payloads.map do |payload|
      Camara::Legislation::Mappers::Voting.call(payload, fetched_at:)
    end
    external_ids = attributes.map { |row| row.fetch(:external_id).dup.freeze }.freeze

    if external_ids.uniq.length != external_ids.length
      raise Camara::Legislation::Mappers::ContractError.new(
        resource: :votings, field: "id", expectation: "expected unique voting identifiers within a page"
      )
    end

    if attributes.any?
      Camara::Legislation::Voting.transaction do
        Camara::Legislation::Voting.upsert_all(attributes, unique_by: :external_id, returning: false)
      end
    end

    external_ids
  end
end
