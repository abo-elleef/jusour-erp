# frozen_string_literal: true

Sidekiq.configure_server do |config|
  config.redis = RedisConfig.client_options
end

Sidekiq.configure_client do |config|
  config.redis = RedisConfig.client_options
end
