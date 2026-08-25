# frozen_string_literal: true

CongregaPlenum.configure do |config|
  config.timeout = Integer(ENV.fetch("CAMARA_API_TIMEOUT", 30))
  config.retries = Integer(ENV.fetch("CAMARA_API_RETRIES", 3))
  config.retry_delay = Float(ENV.fetch("CAMARA_API_RETRY_DELAY", 1.0))
  config.rate_limit_delay = Float(ENV.fetch("CAMARA_API_RATE_LIMIT_DELAY", 0.1))
  config.logger = Rails.logger
end
