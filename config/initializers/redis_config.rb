# frozen_string_literal: true

# Heroku Redis (and similar managed Redis) uses rediss:// with a cert chain that
# often fails OpenSSL verification in Ruby. Skip verify only for TLS URLs.
module RedisConfig
  def self.client_options
    url = ENV.fetch("REDIS_URL", "redis://localhost:6379/0")
    options = { url: url }

    if url.start_with?("rediss://")
      options[:ssl_params] = { verify_mode: OpenSSL::SSL::VERIFY_NONE }
    end

    options
  end
end
