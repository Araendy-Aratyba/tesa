# frozen_string_literal: true

class Camara::Legislation::HydrateVoting
  ResourceResult = Data.define(:hydrated_at, :count)
  Result = Data.define(:external_id, :status, :detail, :votes, :orientations)

  def self.call(...)
    new(...).call
  end

  def initialize(external_id:, detail:, votes:, orientations:)
    @external_id = external_id
    @detail = detail
    @votes = votes
    @orientations = orientations
  end

  def call
    detail = Camara::Legislation::Mappers::Voting.call(@detail.payload, fetched_at: @detail.fetched_at)
    unless detail.fetch(:external_id) == @external_id
      raise Camara::Legislation::Mappers::ContractError.new(
        resource: :voting, field: "id", expectation: "expected the requested voting identifier"
      )
    end

    vote_rows = map_collection(@votes, Camara::Legislation::Mappers::Vote, :deputy_external_id, :votes)
    orientation_rows = map_collection(@orientations, Camara::Legislation::Mappers::Orientation, :group_key, :orientations)

    Camara::Legislation::Voting.transaction do
      voting = Camara::Legislation::Voting.lock.find_by!(external_id: @external_id)
      if superseded?(voting)
        result(voting, :superseded, voting.votes.count, voting.orientations.count)
      else
        voting.update!(
          **detail.except(:external_id, :raw_payload, :fetched_at),
          detail_raw_payload: detail.fetch(:raw_payload), detail_hydrated_at: @detail.fetched_at,
          votes_hydrated_at: @votes.fetched_at, orientations_hydrated_at: @orientations.fetched_at
        )
        reconcile(voting.votes, vote_rows, :deputy_external_id, :index_camara_votes_identity)
        reconcile(voting.orientations, orientation_rows, :group_key, :index_camara_orientations_identity)
        result(voting, :hydrated, vote_rows.length, orientation_rows.length)
      end
    end
  end

  private

  def map_collection(observation, mapper, identity, resource)
    rows = observation.payload.map { |payload| mapper.call(payload, fetched_at: observation.fetched_at) }
    if rows.map { |row| row.fetch(identity) }.uniq.length != rows.length
      raise Camara::Legislation::Mappers::ContractError.new(
        resource:, field: identity, expectation: "expected unique identifiers within a voting"
      )
    end

    rows
  end

  def reconcile(records, rows, identity, index)
    records.upsert_all(rows, unique_by: index, returning: false) if rows.any?
    records.where.not(identity => rows.map { |row| row.fetch(identity) }).delete_all
  end

  def superseded?(voting)
    [
      [ voting.detail_hydrated_at, @detail.fetched_at ],
      [ voting.votes_hydrated_at, @votes.fetched_at ],
      [ voting.orientations_hydrated_at, @orientations.fetched_at ]
    ].any? { |persisted, observed| persisted && persisted > observed }
  end

  def result(voting, status, vote_count, orientation_count)
    Result.new(
      external_id: voting.external_id.dup.freeze,
      status:,
      detail: ResourceResult.new(hydrated_at: voting.detail_hydrated_at&.getutc&.freeze, count: 1),
      votes: ResourceResult.new(hydrated_at: voting.votes_hydrated_at&.getutc&.freeze, count: vote_count),
      orientations: ResourceResult.new(hydrated_at: voting.orientations_hydrated_at&.getutc&.freeze, count: orientation_count)
    )
  end
end
