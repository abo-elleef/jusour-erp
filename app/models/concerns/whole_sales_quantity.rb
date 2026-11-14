# frozen_string_literal: true

# Sales invoice and return lines take whole quantities unless the company's
# owner allows fractions (Setting.allow_fractional_sales_quantities?) — a
# distributor sells by the piece; only a client selling by weight needs 2.5.
#
# The including model names its parent document via #sales_document so
# historical (imported) documents are left alone: they record what the old
# system said, fractions and all. Only a changed quantity is checked, so an
# existing fractional line never blocks an unrelated edit.
module WholeSalesQuantity
  extend ActiveSupport::Concern

  included do
    validate :quantity_whole_unless_fractions_allowed
  end

  private

  def quantity_whole_unless_fractions_allowed
    return if quantity.blank? || !will_save_change_to_quantity?
    return if sales_document&.historical?
    return if Setting.allow_fractional_sales_quantities?
    return if quantity.to_d.frac.zero?

    errors.add(:quantity, :whole_number_required)
  end
end
