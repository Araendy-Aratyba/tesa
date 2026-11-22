# frozen_string_literal: true

class Camara::Legislation::Mappers::Voting
  APPROVAL = { 0 => false, 1 => true, nil => nil }.freeze

  def self.call(payload, fetched_at:)
    source = Camara::Legislation::Mappers::Payload.new(payload, resource: :voting, fetched_at:)

    {
      external_id: source.required("id", source.text(source["id"]), expectation: "expected a nonblank string identifier"),
      occurred_on: source.date("data"),
      registered_at: source.instant("dataHoraRegistro"),
      body_external_id: source.identifier(source["idOrgao"]),
      body_acronym: source.text(source["siglaOrgao"]),
      body_source_uri: source.text(source["uriOrgao"]),
      event_external_id: source.identifier(source["idEvento"]),
      event_source_uri: source.text(source["uriEvento"]),
      description: source.text(source["descricao"]),
      approved: APPROVAL.fetch(source["aprovacao"]) { source.invalid!("aprovacao", "expected 0, 1 or null") },
      source_uri: source.required("uri", source.text(source["uri"]), expectation: "expected a nonblank URI"),
      raw_payload: payload,
      fetched_at: source.fetched_at
    }
  end
end
