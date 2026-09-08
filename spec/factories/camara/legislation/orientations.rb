# frozen_string_literal: true

FactoryBot.define do
  factory :camara_legislation_orientation, class: "Camara::Legislation::Orientation" do
    association :voting, factory: :camara_legislation_voting
    sequence(:group_key) { |n| "uri:https://dadosabertos.camara.leg.br/api/v2/partidos/#{37_900 + n}" }
    leadership_type { "P" }
    sequence(:group_acronym) { |n| "P#{n}" }
    sequence(:group_external_id) { |n| (37_900 + n).to_s }
    group_source_uri do
      "https://dadosabertos.camara.leg.br/api/v2/partidos/#{group_external_id}"
    end
    position { "Sim" }
    fetched_at { Time.current }
    raw_payload do
      {
        "orientacaoVoto" => position,
        "codTipoLideranca" => leadership_type,
        "siglaPartidoBloco" => group_acronym,
        "codPartidoBloco" => group_external_id.to_i,
        "uriPartidoBloco" => group_source_uri
      }
    end

    trait :released do
      position { "Liberado" }
    end

    trait :position_unknown do
      position { nil }
    end

    trait :without_group_uri do
      group_source_uri { nil }
      group_external_id { nil }
      group_key { "leadership:#{leadership_type}:#{group_acronym}" }
    end
  end
end
