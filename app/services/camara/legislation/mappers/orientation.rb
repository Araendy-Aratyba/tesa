# frozen_string_literal: true

class Camara::Legislation::Mappers::Orientation
  def self.call(payload, fetched_at:)
    source = Camara::Legislation::Mappers::Payload.new(payload, resource: :orientation, fetched_at:)
    group_uri = source.text(source["uriPartidoBloco"]) || source.text(source["uriBancada"])
    group_acronym = source.text(source["siglaPartidoBloco"]) || source.text(source["siglaBancada"])
    leadership_type = source.text(source["codTipoLideranca"])

    {
      group_key: group_key(source, group_uri, group_acronym, leadership_type),
      group_acronym:,
      group_external_id: source.identifier(source["codPartidoBloco"]),
      group_source_uri: group_uri,
      leadership_type:,
      position: source.text(source["orientacaoVoto"]) || source.text(source["orientacao"]),
      raw_payload: payload,
      fetched_at: source.fetched_at
    }
  end

  def self.group_key(source, group_uri, group_acronym, leadership_type)
    return "uri:#{group_uri}" if group_uri

    if !leadership_type && !source.text(source["siglaPartidoBloco"]) && group_acronym
      return "bancada:#{normalized_acronym(group_acronym)}"
    end

    acronym = source.required("siglaPartidoBloco", group_acronym, expectation: "expected a nonblank acronym when the URI is absent")
    type = source.required("codTipoLideranca", leadership_type, expectation: "expected a leadership code when the API URI is absent")
    "leadership:#{type.strip}:#{normalized_acronym(acronym)}"
  end
  private_class_method :group_key

  def self.normalized_acronym(acronym)
    acronym.strip.upcase.unicode_normalize
  end
  private_class_method :normalized_acronym
end
