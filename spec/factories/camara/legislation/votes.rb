# frozen_string_literal: true

FactoryBot.define do
  factory :camara_legislation_vote, class: "Camara::Legislation::Vote" do
    association :voting, factory: :camara_legislation_voting
    sequence(:deputy_external_id) { |n| (200_000 + n).to_s }
    position { "Sim" }
    recorded_at { Time.zone.parse("2026-06-10 14:46:15") }
    deputy_source_uri do
      "https://dadosabertos.camara.leg.br/api/v2/deputados/#{deputy_external_id}"
    end
    deputy_name { "Parlamentar Exemplo" }
    party_acronym { "PARTIDO" }
    party_source_uri { "https://dadosabertos.camara.leg.br/api/v2/partidos/123" }
    state_acronym { "DF" }
    legislature_external_id { "57" }
    deputy_photo_url { "https://www.camara.leg.br/internet/deputado/bandep/#{deputy_external_id}.jpg" }
    deputy_email { "dep.exemplo@camara.leg.br" }
    fetched_at { Time.current }
    raw_payload do
      {
        "tipoVoto" => position,
        "dataRegistroVoto" => recorded_at&.iso8601,
        "deputado_" => {
          "id" => deputy_external_id.to_i,
          "uri" => deputy_source_uri,
          "nome" => deputy_name,
          "siglaPartido" => party_acronym,
          "uriPartido" => party_source_uri,
          "siglaUf" => state_acronym,
          "idLegislatura" => legislature_external_id.to_i,
          "urlFoto" => deputy_photo_url,
          "email" => deputy_email
        }
      }
    end

    trait :abstention do
      position { "Abstenção" }
    end

    trait :obstruction do
      position { "Obstrução" }
    end

    trait :position_unknown do
      position { nil }
    end
  end
end
