# frozen_string_literal: true

# Lead and customer phones must be exactly 11 digits when a company turns this
# on (Bazzar: every number is an Egyptian mobile). Off by default, so existing
# companies keep accepting whatever shape they use today.
class AddRequireElevenDigitPhonesToCompanySettings < ActiveRecord::Migration[7.1]
  def change
    add_column :company_settings, :require_eleven_digit_phones, :boolean, null: false, default: false
  end
end
