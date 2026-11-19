# frozen_string_literal: true

module Notifications
  # How a live notification reaches the user, per kind (message_key):
  #
  #   alert — the card stays until opened or closed, and rings.
  #   popup — the card shows, fades on its own after a few seconds, no sound.
  #   quiet — only the bell count goes up.
  #
  # Defaults live here; the owner can override any kind for the company on the
  # Settings page (company_settings.notification_levels, overrides only).
  module Levels
    module_function

    LEVELS = %w[alert popup quiet].freeze
    FALLBACK = "popup"

    DEFAULTS = {
      "customer_invoice_stage_entered" => "alert",
      "customer_invoice_payment_pending" => "alert",
      "cash_variance" => "alert",
      "vendor_balance_negative" => "alert",
      "price_change" => "popup",
      "batch_expiring" => "popup",
      "overtime_shift" => "popup",
      "overtime_weekly" => "popup",
      "low_stock" => "quiet"
    }.freeze

    KEYS = DEFAULTS.keys.freeze

    # The level for one kind in the current company.
    def for(message_key, overrides: self.overrides)
      key = message_key.to_s
      level = overrides[key]
      return level if LEVELS.include?(level)

      DEFAULTS.fetch(key, FALLBACK)
    end

    # Every kind with its level, for the Settings form.
    def all
      current = overrides
      KEYS.index_with { |key| self.for(key, overrides: current) }
    end

    # What to store from the Settings form: known kinds and valid levels only,
    # and nothing that just repeats the default.
    def sanitize(params)
      params.to_h.each_with_object({}) do |(key, level), out|
        key = key.to_s
        level = level.to_s
        next unless KEYS.include?(key) && LEVELS.include?(level)
        next if DEFAULTS[key] == level

        out[key] = level
      end
    end

    def overrides
      CompanySetting.current&.notification_levels || {}
    end
  end
end
