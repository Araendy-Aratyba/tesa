# frozen_string_literal: true

class Camara::Representatives::ImportParties
  Result = Data.define(:record_count)

  CATALOGUE_UPDATE = <<~SQL.squish.freeze
    acronym = excluded.acronym, name = excluded.name, source_uri = excluded.source_uri,
    raw_payload = excluded.raw_payload, fetched_at = excluded.fetched_at, updated_at = excluded.updated_at
    WHERE camara_parties.fetched_at <= excluded.fetched_at
  SQL
  DETAIL_UPDATE = <<~SQL.squish.freeze
    situation = excluded.situation, detail_raw_payload = excluded.detail_raw_payload,
    detail_fetched_at = excluded.detail_fetched_at, updated_at = excluded.updated_at
    WHERE camara_parties.detail_fetched_at IS NULL OR camara_parties.detail_fetched_at <= excluded.detail_fetched_at
  SQL

  def self.call(payloads:, fetched_at:, expected_id: nil)
    rows = payloads.map { |payload| Camara::Representatives::Mappers::Party.call(payload, fetched_at:, detail: !expected_id.nil?) }
    ids = rows.pluck(:external_id)
    unless ids.uniq == ids && (!expected_id || ids == [ expected_id ])
      raise Camara::Representatives::Mappers::ContractError.new(resource: :party, field: "id")
    end

    if rows.any?
      Camara::Representatives::Party.upsert_all(rows.sort_by { |row| row.fetch(:external_id) },
        unique_by: :external_id, returning: false, on_duplicate: Arel.sql(expected_id ? DETAIL_UPDATE : CATALOGUE_UPDATE))
    end
    Result.new(record_count: rows.length)
  end
end
