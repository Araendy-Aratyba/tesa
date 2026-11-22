# frozen_string_literal: true

class Camara::Legislation::Mappers::Vote
  def self.call(payload, fetched_at:)
    source = Camara::Legislation::Mappers::Payload.new(payload, resource: :vote, fetched_at:)
    deputy, id_field = deputy_snapshot(payload)

    {
      deputy_external_id: source.required(id_field, source.identifier(deputy["id"]), expectation: "expected a nonblank string or integer identifier"),
      deputy_source_uri: source.text(deputy["uri"]),
      deputy_name: source.text(deputy["nome"]),
      party_acronym: source.text(deputy["siglaPartido"]),
      party_source_uri: source.text(deputy["uriPartido"]),
      state_acronym: source.text(deputy["siglaUf"]),
      legislature_external_id: source.identifier(deputy["idLegislatura"]),
      deputy_photo_url: source.text(deputy["urlFoto"]),
      deputy_email: source.text(deputy["email"]),
      position: source.text(source["tipoVoto"]) || source.text(source["voto"]),
      recorded_at: source.instant("dataRegistroVoto") || source.instant("dataHoraVoto"),
      raw_payload: payload,
      fetched_at: source.fetched_at
    }
  end

  def self.deputy_snapshot(payload)
    deputy = payload["deputado_"]
    return [ deputy, "deputado_.id" ] if deputy.is_a?(Hash)
    return [ {}, "deputado_.id" ] unless payload.key?("deputado_id")

    snapshot = payload.each_with_object({}) do |(field, value), attributes|
      attributes[field.delete_prefix("deputado_")] = value if field.is_a?(String) && field.start_with?("deputado_")
    end
    [ snapshot, "deputado_id" ]
  end
  private_class_method :deputy_snapshot
end
