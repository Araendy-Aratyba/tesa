# frozen_string_literal: true

module Camara::Representatives::PublicApi
  def self.import_legislatures(...)
    Camara::Representatives::ImportLegislatures.call(...)
  end

  def self.import_parties(...)
    Camara::Representatives::ImportParties.call(...)
  end
end
