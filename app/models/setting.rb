# frozen_string_literal: true

# Thin facade that preserves the Setting.get / Setting.set / Setting.get_int
# interface while delegating to the wide CompanySetting row.
class Setting
  COLUMNS = %w[
    loyalty_earn_rate loyalty_redeem_threshold loyalty_redeem_value_cents
    restaurant_name print_routing print_agent_port print_agent_token
    print_encoding print_code_page arabic_font_path receipt_logo_url
    receipt_footer_text business_day_start_hour
    restrict_stock_transfers_to_source allow_fractional_sales_quantities
    drawer_close_mode require_eleven_digit_phones
    lead_first_follow_up_days lead_follow_up_every_days
  ].freeze

  INTEGER_COLUMNS = %w[
    loyalty_earn_rate loyalty_redeem_threshold loyalty_redeem_value_cents
    print_agent_port print_code_page business_day_start_hour
    lead_first_follow_up_days lead_follow_up_every_days
  ].freeze

  BOOLEAN_COLUMNS = %w[
    restrict_stock_transfers_to_source allow_fractional_sales_quantities require_eleven_digit_phones
  ].freeze

  def self.get(key, default = nil)
    row = CompanySetting.current
    return default unless row
    val = row.public_send(key)
    val.present? ? val : default
  rescue NoMethodError
    default
  end

  def self.set(key, value)
    row = CompanySetting.current_or_initialize
    typed_value =
      if BOOLEAN_COLUMNS.include?(key.to_s)
        ActiveModel::Type::Boolean.new.cast(value)
      elsif INTEGER_COLUMNS.include?(key.to_s)
        value.to_i
      else
        value.to_s
      end
    row.public_send(:"#{key}=", typed_value)
    row.save!
    row
  end

  def self.get_int(key, default = 0)
    get(key, default).to_i
  end

  def self.get_bool(key, default = false)
    row = CompanySetting.current
    return default unless row&.has_attribute?(key)

    value = row.public_send(key)
    return default if value.nil?

    ActiveModel::Type::Boolean.new.cast(value)
  rescue NoMethodError
    default
  end

  # When true, transfers cannot send more than source on-hand / batches.
  # When false, overselling is allowed and source quantity can go negative.
  def self.restrict_stock_transfers_to_source?
    get_bool("restrict_stock_transfers_to_source", true)
  end

  # Sales invoices and returns take whole quantities unless the owner allows
  # fractions (a client selling by weight). Off by default.
  def self.allow_fractional_sales_quantities?
    get_bool("allow_fractional_sales_quantities", false)
  end

  # Lead and customer phones must be exactly 11 digits (see ContactPhones).
  # Off by default.
  def self.require_eleven_digit_phones?
    get_bool("require_eleven_digit_phones", false)
  end

  # Lead follow-up cadence (see Lead). The first follow-up lands this many days
  # after a lead is created; each logged contact moves the next one this many
  # days past the contact. 0 (or blank) turns that part off. Column defaults
  # are 1 and 3, so a company that never saved the form gets those.
  def self.lead_first_follow_up_days
    days_setting("lead_first_follow_up_days")
  end

  def self.lead_follow_up_every_days
    days_setting("lead_follow_up_every_days")
  end

  # Either part on means the company runs the cadence, and the morning
  # follow-up notification goes out (leads:notify_follow_ups).
  def self.lead_follow_up_cadence?
    lead_first_follow_up_days.positive? || lead_follow_up_every_days.positive?
  end

  def self.days_setting(key)
    row = CompanySetting.current
    value = row ? row.public_send(key) : CompanySetting.column_defaults[key]
    [value.to_i, 0].max
  end
  private_class_method :days_setting

  DRAWER_CLOSE_MODES = %w[documented simple].freeze

  # How a drawer close books an over/short count.
  #   documented (default) — the safe gets the expected cash; the gap becomes an
  #     Income (over) or a voucher to the cashier (short). See
  #     Accounting::DrawerVarianceDocuments.
  #   simple — the safe gets what was counted; the gap is shown but not booked.
  def self.drawer_close_mode
    mode = get("drawer_close_mode", "documented").to_s
    DRAWER_CLOSE_MODES.include?(mode) ? mode : "documented"
  end

  def self.document_drawer_variance?
    drawer_close_mode == "documented"
  end
end
