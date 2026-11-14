# frozen_string_literal: true

# Distribution clients sell by the piece, so sales and returns take whole
# quantities unless the owner turns fractions on (for a client that sells by
# weight). Off by default: a new company sells in whole numbers.
class AddAllowFractionalSalesQuantitiesToCompanySettings < ActiveRecord::Migration[7.1]
  def change
    add_column :company_settings, :allow_fractional_sales_quantities, :boolean, null: false, default: false
  end
end
