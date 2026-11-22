# frozen_string_literal: true

module Camara::Ingestion::RepresentativeCatalogs
  Definition = Data.define(:source, :import_method)
  CATALOGS = {
    "legislatures" => Definition.new(source: CongregaPlenum::LegislaturesService, import_method: :import_legislatures),
    "parties" => Definition.new(source: CongregaPlenum::PartiesService, import_method: :import_parties)
  }.freeze

  def self.fetch(resource)
    CATALOGS.fetch(resource.to_s) { raise ArgumentError, "unknown representative catalogue" }
  end
end
