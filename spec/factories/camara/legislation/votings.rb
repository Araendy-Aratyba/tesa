# frozen_string_literal: true

FactoryBot.define do
  factory :camara_legislation_voting, class: "Camara::Legislation::Voting" do
    sequence(:external_id) { |n| "2355754-#{n}" }
    occurred_on { Date.new(2026, 1, 15) }
    source_uri { "https://dadosabertos.camara.leg.br/api/v2/votacoes/#{external_id}" }
    fetched_at { Time.current }
    raw_payload { { "id" => external_id, "uri" => source_uri, "data" => occurred_on.iso8601 } }

    trait :approved do
      approved { true }
    end

    trait :rejected do
      approved { false }
    end

    trait :approval_unknown do
      approved { nil }
    end
  end
end
