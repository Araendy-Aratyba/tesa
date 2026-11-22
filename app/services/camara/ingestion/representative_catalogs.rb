# frozen_string_literal: true

module Camara::Ingestion::RepresentativeCatalogs
  Definition = Data.define(:source, :import_method, :legislature_scoped)
  CATALOGS = {
    "legislatures" => Definition.new(source: CongregaPlenum::LegislaturesService, import_method: :import_legislatures, legislature_scoped: false),
    "parties" => Definition.new(source: CongregaPlenum::PartiesService, import_method: :import_parties, legislature_scoped: false),
    "deputies" => Definition.new(source: CongregaPlenum::CongressmenService, import_method: :import_deputies, legislature_scoped: true)
  }.freeze

  def self.fetch(resource)
    CATALOGS.fetch(resource.to_s) { raise ArgumentError, "unknown representative catalogue" }
  end
end
