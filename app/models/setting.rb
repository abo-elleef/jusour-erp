# frozen_string_literal: true

# Thin facade that preserves the Setting.get / Setting.set / Setting.get_int
# interface while delegating to the wide CompanySetting row.
class Setting
  COLUMNS = %w[
    loyalty_earn_rate loyalty_redeem_threshold loyalty_redeem_value_cents
    restaurant_name print_routing print_agent_port print_agent_token
    print_encoding print_code_page arabic_font_path receipt_logo_url
    receipt_footer_text business_day_start_hour
    restrict_stock_transfers_to_source
  ].freeze

  INTEGER_COLUMNS = %w[
    loyalty_earn_rate loyalty_redeem_threshold loyalty_redeem_value_cents
    print_agent_port print_code_page business_day_start_hour
  ].freeze

  BOOLEAN_COLUMNS = %w[restrict_stock_transfers_to_source].freeze

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
end
