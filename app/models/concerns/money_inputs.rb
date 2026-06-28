# frozen_string_literal: true

# Generates human-facing _pounds virtual attributes for _cents DB columns.
# The form field uses the _pounds attr (accepts 19.99); the DB stores the integer (1999).
#
# Usage:
#   money_input :amount_cents          # generates amount_pounds / amount_pounds=
#   money_input :base_price_cents      # generates base_price_pounds / base_price_pounds=
module MoneyInputs
  extend ActiveSupport::Concern

  class_methods do
    def money_input(*cents_attrs)
      cents_attrs.each do |cents_attr|
        pounds_attr = cents_attr.to_s.sub(/_cents$/, "_pounds")

        define_method(pounds_attr) do
          cents = public_send(cents_attr)
          cents.nil? ? nil : (cents / 100.0)
        end

        define_method(:"#{pounds_attr}=") do |val|
          public_send(:"#{cents_attr}=", val.present? ? (val.to_f * 100).round : nil)
        end
      end
    end
  end
end
