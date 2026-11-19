# frozen_string_literal: true

# Phone hygiene shared by Lead and Customer (`phone` + `phone_secondary`).
#
# * Before validation, a phone that is new or being changed is normalised:
#   Arabic-Indic / Persian digits become Latin, spaces and dashes are dropped.
#   The normalised value is what gets stored.
# * When the company turns on `require_eleven_digit_phones` (company settings,
#   off by default), each phone must be exactly 11 digits.
#
# Both only touch a phone on create or when that phone changes, so existing rows
# with old-shaped numbers keep saving until someone edits the number itself.
#
# `skip_phone_length_check` lets a system path (online orders, offline sync,
# lead conversion) keep a number a person already accepted elsewhere instead of
# failing an order or a conversion over its length.
module ContactPhones
  extend ActiveSupport::Concern

  PHONE_COLUMNS = %w[phone phone_secondary].freeze
  ARABIC_DIGITS = Phones::EgyptianMobile::ARABIC_DIGITS
  LATIN_DIGITS = Phones::EgyptianMobile::LATIN_DIGITS
  # Spaces (incl. non-breaking), ASCII and Unicode dashes, and the invisible
  # direction marks that ride along when a number is pasted from Arabic text.
  SEPARATORS = /[[:space:]\-‐-―‎‏؜]/
  ELEVEN_DIGITS = /\A\d{11}\z/

  included do
    attr_accessor :skip_phone_length_check

    before_validation :normalize_contact_phones
    validate :contact_phones_have_eleven_digits
  end

  class_methods do
    # SQL that reads a stored phone column the way #normalize_phone writes it,
    # so a new number matches an old row stored as "0100 123-4567" or in Arabic digits.
    def normalized_phone_sql(column)
      "regexp_replace(translate(#{column}, '#{ARABIC_DIGITS}', '#{LATIN_DIGITS}'), " \
        "'[\\s ‐-―‎‏؜-]', '', 'g')" # \s, not [:space:], which clashes with :binds

    end
  end

  def self.normalize_phone(raw)
    raw.to_s.tr(ARABIC_DIGITS, LATIN_DIGITS).gsub(SEPARATORS, "").presence
  end

  private

  # The phone columns this save is setting (any phone on create; only an edited
  # one on update) and that hold a value.
  def contact_phone_columns_to_check
    PHONE_COLUMNS.select do |column|
      self[column].present? && (new_record? || will_save_change_to_attribute?(column))
    end
  end

  def normalize_contact_phones
    PHONE_COLUMNS.each do |column|
      next unless new_record? || will_save_change_to_attribute?(column)

      self[column] = ContactPhones.normalize_phone(self[column])
    end
  end

  def contact_phones_have_eleven_digits
    return if skip_phone_length_check
    return unless eleven_digit_phones_required?

    contact_phone_columns_to_check.each do |column|
      next if self[column].match?(ELEVEN_DIGITS)

      # Arabic error messages are shown without the field name, so it's passed in.
      errors.add(column, I18n.t("phones.errors.eleven_digits", field: self.class.human_attribute_name(column)))
    end
  end

  def eleven_digit_phones_required?
    return false if company_id.blank?

    CompanySetting.where(company_id: company_id).pick(:require_eleven_digit_phones) == true
  end
end
