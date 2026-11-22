# frozen_string_literal: true

require "spec_helper"
require "json"

ENV["RAILS_ENV"] ||= "test"
require_relative "../../config/environment"

RSpec.shared_context "legislation mapper payloads" do
  let(:fetched_at) { Time.utc(2026, 8, 5, 21) }

  def payload_fixture(name)
    path = File.expand_path("../fixtures/camara/legislation/#{name}.json", __dir__)
    JSON.parse(File.read(path))
  end
end
