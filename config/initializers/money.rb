# frozen_string_literal: true

MoneyRails.configure do |config|
  config.default_currency = :usd
  config.no_cents_if_whole = false
  config.rounding_mode = BigDecimal::ROUND_HALF_UP
end
