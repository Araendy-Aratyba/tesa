# frozen_string_literal: true

class Camara::Representatives::ImportDeputies
  Result = Data.define(:record_count)

  def self.call(payloads:, fetched_at:, legislature_id: nil, expected_id: nil)
    if expected_id
      detail = payloads.one? && Camara::Representatives::Mappers::Deputy.detail(payloads.first, fetched_at:)
      unless detail && detail.fetch(:external_id) == expected_id
        raise Camara::Representatives::Mappers::ContractError.new(resource: :deputy, field: "id")
      end

      persist_detail(detail)
    else
      raise ArgumentError, "deputy catalogue requires the queried legislature ID" unless legislature_id.to_s.match?(/\A[1-9][0-9]*\z/)

      rows = payloads.map do |payload|
        Camara::Representatives::Mappers::DeputyListingObservation.call(payload, legislature_id:, fetched_at:)
      end
      persist_list(rows) if rows.any?
    end
    Result.new(record_count: payloads.size)
  end

  def self.persist_detail(detail)
    deputies = Camara::Representatives::Deputy
    write = lambda do
      deputies.upsert_all([ detail ], unique_by: :external_id, returning: false,
        on_duplicate: Arel.sql(<<~SQL.squish))
          source_uri = excluded.source_uri, civil_name = excluded.civil_name, electoral_name = excluded.electoral_name,
          state_acronym = excluded.state_acronym, situation = excluded.situation, party_acronym = excluded.party_acronym,
          party_source_uri = excluded.party_source_uri, current_legislature_external_id = excluded.current_legislature_external_id,
          raw_payload = excluded.raw_payload, fetched_at = excluded.fetched_at, updated_at = excluded.updated_at
          WHERE camara_deputies.fetched_at IS NULL OR camara_deputies.fetched_at <= excluded.fetched_at
        SQL
    end
    # Bulk inserts inline the raw detail in SQL, which can contain a government identifier.
    logger = ActiveRecord::Base.logger
    logger ? logger.silence { write.call } : write.call
  end
  private_class_method :persist_detail

  def self.persist_list(rows)
    identities = rows.map(&:first).uniq { |identity| identity.fetch(:external_id) }.sort_by { |identity| identity.fetch(:external_id) }
    deputies = Camara::Representatives::Deputy
    deputies.transaction do
      deputies.insert_all(identities, unique_by: :external_id, returning: false)
      ids = deputies.where(external_id: identities.pluck(:external_id)).pluck(:external_id, :id).to_h
      observations = rows.map do |identity, observation|
        observation.merge(deputy_id: ids.fetch(identity.fetch(:external_id)))
      end
      persist_observations(observations)
    end
  end
  private_class_method :persist_list

  def self.persist_observations(observations)
    rows = observations.uniq { |row| row.values_at(:deputy_id, :payload_fingerprint) }
    Camara::Representatives::DeputyListingObservation.upsert_all(rows.sort_by { |row| row.values_at(:deputy_id, :payload_fingerprint) },
      unique_by: :index_camara_deputy_listing_identity, returning: false, on_duplicate: Arel.sql(<<~SQL.squish))
        first_seen_at = LEAST(camara_deputy_listing_observations.first_seen_at, excluded.first_seen_at),
        last_seen_at = GREATEST(camara_deputy_listing_observations.last_seen_at, excluded.last_seen_at),
        updated_at = excluded.updated_at
      SQL
  end
  private_class_method :persist_observations
end
