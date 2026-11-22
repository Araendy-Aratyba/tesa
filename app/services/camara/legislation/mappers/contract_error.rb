# frozen_string_literal: true

class Camara::Legislation::Mappers::ContractError < StandardError
  attr_reader :resource, :field

  def initialize(resource:, field:, expectation:)
    @resource = resource
    @field = field

    super("#{resource}.#{field}: #{expectation}")
  end
end
