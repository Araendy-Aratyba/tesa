# frozen_string_literal: true

FactoryBot.define do
  factory :camara_representatives_legislature, class: "Camara::Representatives::Legislature" do
    sequence(:number)
    external_id { number.to_s }
    source_uri { "https://dadosabertos.camara.leg.br/api/v2/legislaturas/#{external_id}" }
    starts_on { Date.new(2023, 2, 1) }
    ends_on { Date.new(2027, 1, 31) }
    fetched_at { Time.current }
    raw_payload { { "id" => number, "uri" => source_uri } }
  end
end
