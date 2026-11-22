# frozen_string_literal: true

require "support/legislation_mapper_spec_helper"

RSpec.describe Camara::Legislation::Mappers::Orientation do
  include_context "legislation mapper payloads"

  let(:payload) { payload_fixture("orientation") }

  it "prefers the complete group URI while retaining the source leadership fields" do
    uri = payload["uriPartidoBloco"]

    expect(described_class.call(payload.freeze, fetched_at:)).to eq(
      group_key: "uri:#{uri}",
      group_external_id: "900",
      group_source_uri: uri,
      group_acronym: "PFX",
      leadership_type: "P",
      position: "Liberado",
      raw_payload: payload_fixture("orientation"),
      fetched_at:
    )
  end

  it "derives a key from the leadership code and normalized acronym when the API URI is absent" do
    api_row = payload.merge("uriPartidoBloco" => nil, "codTipoLideranca" => "B", "siglaPartidoBloco" => "  Oposição  ",
      "codPartidoBloco" => nil, "orientacaoVoto" => "")

    expect(described_class.call(api_row, fetched_at:)).to include(
      group_key: "leadership:B:OPOSIÇÃO", group_external_id: nil, group_acronym: "  Oposição  ", position: nil
    )
  end

  it "maps an annual record with a URI to the same URI key" do
    annual = { "uriBancada" => payload["uriPartidoBloco"], "siglaBancada" => "PFX", "orientacao" => "Não" }

    expect(described_class.call(annual, fetched_at:)).to include(
      group_key: "uri:#{annual["uriBancada"]}", group_external_id: nil, leadership_type: nil, position: "Não", raw_payload: annual
    )
  end

  it "uses the published annual acronym when the file has no URI or leadership code" do
    annual = { "uriBancada" => "", "siglaBancada" => "Minoria", "orientacao" => "Posição nova" }

    expect(described_class.call(annual, fetched_at:)).to include(
      group_key: "bancada:MINORIA", leadership_type: nil, group_acronym: "Minoria", position: "Posição nova", raw_payload: annual
    )
  end

  it "reports the missing API leadership code if the URI is absent" do
    incomplete = payload.except("uriPartidoBloco", "codTipoLideranca")

    expect { described_class.call(incomplete, fetched_at:) }.to raise_error(
      Camara::Legislation::Mappers::ContractError, /orientation\.codTipoLideranca/
    )
  end

  it "rejects a record with no group identity" do
    expect { described_class.call({ "orientacao" => "Sim" }, fetched_at:) }.to raise_error(
      Camara::Legislation::Mappers::ContractError, /orientation\.siglaPartidoBloco/
    )
  end
end
