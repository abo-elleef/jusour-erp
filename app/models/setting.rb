# frozen_string_literal: true

# Thin facade that preserves the Setting.get / Setting.set / Setting.get_int
# interface while delegating to the wide CompanySetting row.
class Setting
  COLUMNS = %w[
    loyalty_earn_rate loyalty_redeem_threshold loyalty_redeem_value_cents
    restaurant_name print_routing print_agent_port print_agent_token
    print_encoding print_code_page arabic_font_path receipt_logo_url
    receipt_footer_text
  ].freeze

  INTEGER_COLUMNS = %w[
    loyalty_earn_rate loyalty_redeem_threshold loyalty_redeem_value_cents
    print_agent_port print_code_page
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
    typed_value = INTEGER_COLUMNS.include?(key.to_s) ? value.to_i : value.to_s
    row.public_send(:"#{key}=", typed_value)
    row.save!
    row
  end

  def self.get_int(key, default = 0)
    get(key, default).to_i
  end

end
