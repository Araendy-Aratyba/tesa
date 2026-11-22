# frozen_string_literal: true

require "support/legislation_mapper_spec_helper"

RSpec.describe Camara::Legislation::Mappers::Vote do
  include_context "legislation mapper payloads"

  let(:payload) { payload_fixture("vote") }

  it "maps a published deputy snapshot with UTF-8 values" do
    deputy = payload["deputado_"].freeze

    expect(described_class.call(payload.freeze, fetched_at:)).to eq(
      deputy_external_id: "900001",
      deputy_source_uri: deputy["uri"],
      deputy_name: "João da Conceição",
      party_acronym: "PFX",
      party_source_uri: deputy["uriPartido"],
      state_acronym: "SP",
      legislature_external_id: "57",
      deputy_photo_url: deputy["urlFoto"],
      deputy_email: deputy["email"],
      position: "Obstrução",
      recorded_at: Time.utc(2026, 8, 4, 21, 30),
      raw_payload: payload_fixture("vote"),
      fetched_at:
    )
  end

  it "maps flat annual vote fields without converting external IDs to numbers" do
    annual = {
      "idVotacao" => "0001234-35",
      "deputado_id" => "000009",
      "deputado_nome" => "Deputada de Exemplo",
      "deputado_siglaPartido" => "PFX",
      "deputado_siglaUf" => "RJ",
      "deputado_idLegislatura" => "057",
      "voto" => "Posição nova",
      "dataHoraVoto" => "2026-08-04T21:30:00Z"
    }

    expect(described_class.call(annual, fetched_at:)).to include(
      deputy_external_id: "000009",
      deputy_name: "Deputada de Exemplo",
      party_acronym: "PFX",
      state_acronym: "RJ",
      legislature_external_id: "057",
      position: "Posição nova",
      recorded_at: Time.utc(2026, 8, 4, 21, 30),
      raw_payload: annual
    )
  end

  it "keeps an empty position and date unknown" do
    result = described_class.call(payload.merge("tipoVoto" => "", "dataRegistroVoto" => nil), fetched_at:)

    expect(result).to include(position: nil, recorded_at: nil)
  end

  it "rejects a non-object payload" do
    expect { described_class.call(nil, fetched_at:) }.to raise_error(Camara::Legislation::Mappers::ContractError, /vote\.payload/)
  end

  it "reports an invalid nested identity at its source field" do
    expect { described_class.call(payload.merge("deputado_" => { "id" => [] }), fetched_at:) }.to raise_error(
      Camara::Legislation::Mappers::ContractError, /vote\.deputado_\.id/
    )
  end

  it "reports an invalid annual timestamp at its source field" do
    annual = { "deputado_id" => "000009", "dataHoraVoto" => "2026-08-04T25:00:00" }

    expect { described_class.call(annual, fetched_at:) }.to raise_error(
      Camara::Legislation::Mappers::ContractError, /vote\.dataHoraVoto/
    )
  end
end
