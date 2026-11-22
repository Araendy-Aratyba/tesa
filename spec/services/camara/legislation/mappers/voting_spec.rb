# frozen_string_literal: true

require "support/legislation_mapper_spec_helper"

RSpec.describe Camara::Legislation::Mappers::Voting do
  include_context "legislation mapper payloads"

  let(:summary) { payload_fixture("voting_summary") }
  let(:detail) { payload_fixture("voting_detail") }

  it "maps a summary without inferring approval or occurrence time from its text" do
    expect(described_class.call(summary.freeze, fetched_at:)).to eq(
      external_id: "0001234-35",
      occurred_on: Date.new(2026, 8, 4),
      registered_at: Time.utc(2026, 8, 5, 4, 25, 50),
      body_external_id: nil,
      body_acronym: "PLEN",
      body_source_uri: summary["uriOrgao"],
      event_external_id: nil,
      event_source_uri: nil,
      description: "Aprovada a redação final da proposição.",
      approved: nil,
      source_uri: summary["uri"],
      raw_payload: payload_fixture("voting_summary"),
      fetched_at:
    )
  end

  it "maps details with their explicit offset and preserves possible objects and affected propositions" do
    attributes = described_class.call(detail, fetched_at: fetched_at.in_time_zone("Brasilia"))

    expect(attributes).to include(
      occurred_on: Date.new(2026, 8, 4),
      registered_at: Time.utc(2026, 8, 5, 4, 25, 50.250),
      body_external_id: "900",
      event_external_id: "91234",
      event_source_uri: detail["uriEvento"],
      approved: false,
      fetched_at:,
      raw_payload: payload_fixture("voting_detail")
    )
    expect(attributes.values_at(:registered_at, :fetched_at)).to all(be_utc)
  end

  it "distinguishes explicit null and approval" do
    expect(described_class.call(summary.merge("aprovacao" => nil), fetched_at:)[:approved]).to be_nil
    expect(described_class.call(summary.merge("aprovacao" => 1), fetched_at:)[:approved]).to be(true)
  end

  it "allows missing optional attributes and retains unsupported optional values in the raw payload" do
    payload = summary.except("dataHoraRegistro", "siglaOrgao").merge("idEvento" => [ 10 ])

    expect(described_class.call(payload, fetched_at:)).to include(
      registered_at: nil, body_acronym: nil, event_external_id: nil, raw_payload: payload
    )
  end

  [ nil, [], "invalid" ].each do |payload|
    it "rejects a #{payload.class} in place of the JSON object" do
      expect { described_class.call(payload, fetched_at:) }.to raise_error(
        Camara::Legislation::Mappers::ContractError, /voting\.payload/
      )
    end
  end

  { "id" => 1234, "uri" => " ", "data" => "2026-02-29" }.each do |field, value|
    it "rejects an invalid #{field}" do
      expect { described_class.call(summary.merge(field => value), fetched_at:) }.to raise_error(
        Camara::Legislation::Mappers::ContractError, /voting\.#{field}:/
      )
    end
  end

  it "names the missing identity field and omits the payload from its error" do
    payload = summary.except("id").merge("descricao" => "Text that must not be logged")

    expect { described_class.call(payload, fetched_at:) }.to raise_error(Camara::Legislation::Mappers::ContractError) do |error|
      expect(error).to have_attributes(resource: :voting, field: "id")
      expect(error.message).not_to include(payload["descricao"])
    end
  end

  [ false, "1", 1.0, 2 ].each do |approval|
    it "rejects #{approval.inspect} as an unsupported approval value" do
      expect { described_class.call(summary.merge("aprovacao" => approval), fetched_at:) }.to raise_error(
        Camara::Legislation::Mappers::ContractError, /voting\.aprovacao/
      )
    end
  end

  [ "2026-08-04", "2026-08-04T24:00:00", "2026-08-04T23:00:00+95:00",
    "2018-11-04T00:30:00", "2019-02-16T23:30:00" ].each do |timestamp|
    it "rejects the invalid or ambiguous timestamp #{timestamp}" do
      expect { described_class.call(summary.merge("dataHoraRegistro" => timestamp), fetched_at:) }.to raise_error(
        Camara::Legislation::Mappers::ContractError, /voting\.dataHoraRegistro/
      )
    end
  end

  it "accepts an explicit offset at a wall time repeated in Brasilia" do
    [ "-02:00", "-0200", "-02" ].each do |offset|
      payload = summary.merge("dataHoraRegistro" => "2019-02-16T23:30:00#{offset}")

      expect(described_class.call(payload, fetched_at:)[:registered_at]).to eq(Time.utc(2019, 2, 17, 1, 30))
    end
  end

  it "requires the observation time from the caller" do
    expect { described_class.call(summary, fetched_at: nil) }.to raise_error(
      Camara::Legislation::Mappers::ContractError, /voting\.fetched_at/
    )
  end
end
