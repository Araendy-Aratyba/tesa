# frozen_string_literal: true

class Camara::Ingestion::HydrateVoting
  Observation = Data.define(:payload, :fetched_at)
  FETCH_METHODS = { detail: :fetch_by_id, votes: :fetch_votes, orientations: :fetch_orientations }.freeze

  class FetchError < StandardError
    attr_reader :resource, :fetched_resources

    def initialize(resource:, fetched_resources:)
      @resource = resource
      @fetched_resources = fetched_resources.freeze
      super("could not fetch voting #{resource}")
    end
  end

  def self.call(external_id:, client: Camara::Ingestion::VotingHydrationSource)
    new(external_id:, client:).call
  end

  def initialize(external_id:, client:)
    @external_id = external_id
    @client = client
  end

  def call
    unless @external_id.is_a?(String) && @external_id.present?
      raise ArgumentError, "a voting external ID is required"
    end
    if ApplicationRecord.current_transaction.open?
      raise ArgumentError, "voting hydration must run outside a database transaction"
    end

    observations = {}
    FETCH_METHODS.each do |resource, method|
      observations[resource] = fetch(resource, method, observations.keys)
    end
    Camara::Legislation::PublicApi.hydrate_voting(external_id: @external_id, **observations)
  end

  private

  def fetch(resource, method, fetched_resources)
    payload = @client.public_send(method, @external_id)
    expected_type = resource == :detail ? Hash : Array
    unless payload.is_a?(expected_type)
      raise CongregaPlenum::APIError, "expected #{expected_type} for voting #{resource}"
    end

    Observation.new(payload:, fetched_at: Time.current.getutc.freeze)
  rescue CongregaPlenum::Error
    raise FetchError.new(resource:, fetched_resources:)
  end
end
