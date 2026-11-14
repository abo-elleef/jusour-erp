# frozen_string_literal: true

# Quantities are stored as decimal(12,3), so a whole sale reads back as "3.0".
# Show whole numbers without the trailing ".0" (in inputs and on documents),
# and fractional ones without padding zeros ("2.5", not "2.500").
module SalesQuantityHelper
  def sales_quantity_value(quantity)
    return nil if quantity.blank?

    d = quantity.to_d
    d.frac.zero? ? d.to_i.to_s : d.to_s("F").sub(/0+\z/, "")
  end
end
