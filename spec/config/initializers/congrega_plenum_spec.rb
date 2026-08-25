# frozen_string_literal: true

require "rails_helper"

RSpec.describe "CongregaPlenum initializer" do
  ENVIRONMENT_VARIABLES = %w[
    CAMARA_API_TIMEOUT
    CAMARA_API_RETRIES
    CAMARA_API_RETRY_DELAY
    CAMARA_API_RATE_LIMIT_DELAY
  ].freeze

  around do |example|
    previous_configuration = CongregaPlenum.configuration
    previous_environment = ENVIRONMENT_VARIABLES.to_h { |name| [ name, ENV[name] ] }

    CongregaPlenum.configuration = CongregaPlenum::Configuration.new
    ENVIRONMENT_VARIABLES.each { |name| ENV.delete(name) }

    example.run
  ensure
    previous_environment.each do |name, value|
      value.nil? ? ENV.delete(name) : ENV[name] = value
    end
    CongregaPlenum.configuration = previous_configuration
  end

  it "uses documented defaults without changing the official API URL" do
    load_initializer

    expect(CongregaPlenum.configuration).to have_attributes(
      base_url: "https://dadosabertos.camara.leg.br/api/v2",
      timeout: 30,
      retries: 3,
      retry_delay: 1.0,
      rate_limit_delay: 0.1,
      logger: Rails.logger
    )
  end

  it "uses operational values from the environment" do
    ENV.update(
      "CAMARA_API_TIMEOUT" => "45",
      "CAMARA_API_RETRIES" => "6",
      "CAMARA_API_RETRY_DELAY" => "2.5",
      "CAMARA_API_RATE_LIMIT_DELAY" => "0.25"
    )

    load_initializer

    expect(CongregaPlenum.configuration).to have_attributes(
      timeout: 45,
      retries: 6,
      retry_delay: 2.5,
      rate_limit_delay: 0.25,
      logger: Rails.logger
    )
  end

  def load_initializer
    load Rails.root.join("config/initializers/congrega_plenum.rb")
  end
end

RSpec.describe "application time configuration" do
  it "interprets local times in Brasilia and persists instants in UTC" do
    expect(Rails.application.config.time_zone).to eq("Brasilia")
    expect(ActiveRecord.default_timezone).to eq(:utc)
  end
end
