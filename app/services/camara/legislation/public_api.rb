# frozen_string_literal: true

module Camara::Legislation::PublicApi
  def self.import_votings_page(payloads:, fetched_at:)
    Camara::Legislation::ImportVotingsPage.call(payloads:, fetched_at:)
  end
end
