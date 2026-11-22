# frozen_string_literal: true

require "rails_helper"
require "stringio"

RSpec.describe Camara::Representatives::ImportDeputies do
  it "preserves raw detail for provenance without writing its government identifier to SQL debug logs" do
    payload = {
      "id" => 10002, "uri" => "https://example.org/deputados/10002", "cpf" => "synthetic-identifier",
      "ultimoStatus" => { "nomeEleitoral" => "Nome Exemplo" }
    }
    output = StringIO.new
    logger = ActiveSupport::Logger.new(output)
    previous = ActiveRecord::Base.logger
    ActiveRecord::Base.logger = logger

    described_class.call(payloads: [ payload ], fetched_at: Time.current, expected_id: "10002")

    expect(Camara::Representatives::Deputy.find_by!(external_id: "10002").raw_payload).to eq(payload)
    expect(output.string).to include("SELECT", "camara_deputies")
    expect(output.string).not_to include("synthetic-identifier")
  ensure
    ActiveRecord::Base.logger = previous
  end
end
