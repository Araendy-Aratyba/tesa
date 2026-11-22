# frozen_string_literal: true

module Camara::Legislation::PublicApi
  def self.import_votings_page(payloads:, fetched_at:)
    Camara::Legislation::ImportVotingsPage.call(payloads:, fetched_at:)
  end

  def self.hydrate_voting(external_id:, detail:, votes:, orientations:)
    Camara::Legislation::HydrateVoting.call(external_id:, detail:, votes:, orientations:)
  end
end
