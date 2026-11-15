# frozen_string_literal: true

module Phones
  # Egyptian mobile numbers in every shape customers type them:
  # "01012345678", "+20 101 234 5678", "00201012345678", "٠١٠١٢٣٤٥٦٧٨".
  # #normalize returns the local 11-digit form ("01012345678") — the form cashiers
  # type into the POS — or nil when it isn't an Egyptian mobile.
  module EgyptianMobile
    ARABIC_DIGITS = "٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹"
    LATIN_DIGITS = "01234567890123456789"
    LOCAL = /\A01[0125]\d{8}\z/

    module_function

    def normalize(raw)
      digits = raw.to_s.tr(ARABIC_DIGITS, LATIN_DIGITS).gsub(/\D/, "")
      digits = digits.delete_prefix("00")
      digits = "0#{digits.delete_prefix('20')}" if digits.start_with?("201") && digits.length == 12
      digits.match?(LOCAL) ? digits : nil
    end

    # Every way the same number may already be stored on a customer.
    def variants(local)
      return [] if local.blank?

      rest = local.delete_prefix("0")
      [local, "+20#{rest}", "20#{rest}", "0020#{rest}", "+20 #{rest}"]
    end
  end
end
