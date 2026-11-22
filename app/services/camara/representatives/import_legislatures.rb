# frozen_string_literal: true

class Camara::Representatives::ImportLegislatures
  Result = Data.define(:record_count)

  def self.call(payloads:, fetched_at:, expected_id: nil)
    rows = payloads.map { |payload| Camara::Representatives::Mappers::Legislature.call(payload, fetched_at:) }
    ids = rows.pluck(:external_id)
    unless ids.uniq == ids && (!expected_id || ids == [ expected_id ])
      raise Camara::Representatives::Mappers::ContractError.new(resource: :legislature, field: "id")
    end

    if rows.any?
      Camara::Representatives::Legislature.upsert_all(rows.sort_by { |row| row.fetch(:external_id) },
        unique_by: :external_id, returning: false, on_duplicate: Arel.sql(<<~SQL.squish))
          number = excluded.number, source_uri = excluded.source_uri, starts_on = excluded.starts_on,
          ends_on = excluded.ends_on, election_year = excluded.election_year, raw_payload = excluded.raw_payload,
          fetched_at = excluded.fetched_at, updated_at = excluded.updated_at
          WHERE camara_legislatures.fetched_at <= excluded.fetched_at
        SQL
    end
    Result.new(record_count: rows.length)
  end
end
