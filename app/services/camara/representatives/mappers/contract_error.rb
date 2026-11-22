# frozen_string_literal: true

class Camara::Representatives::Mappers::ContractError < StandardError
  def initialize(resource:, field:)
    super("invalid #{resource} payload for #{field}")
  end
end
