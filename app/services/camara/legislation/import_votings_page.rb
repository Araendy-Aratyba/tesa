# frozen_string_literal: true

class Camara::Legislation::ImportVotingsPage
  DETAIL_IDENTIFIERS = { body_external_id: "idOrgao", event_external_id: "idEvento" }.freeze

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
        attributes.group_by { |row| omitted_identifiers(row.fetch(:raw_payload)) }.each do |omitted, rows|
          update_only = rows.first.keys - omitted - [ :external_id ]
          Camara::Legislation::Voting.upsert_all(rows, unique_by: :external_id, update_only:, returning: false)
        end
      end
    end

    external_ids
  end

  def self.omitted_identifiers(payload)
    DETAIL_IDENTIFIERS.filter_map { |attribute, field| attribute unless payload.key?(field) }
  end
  private_class_method :omitted_identifiers
end
