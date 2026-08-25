# frozen_string_literal: true

class AddImportFieldsToCustomers < ActiveRecord::Migration[7.1]
  def change
    add_column :customers, :notes, :text
    # Reference back to the customer's id in the previous system, for de-duping
    # imports and reconciliation. Not guaranteed unique in the source data, so
    # this is a plain lookup index rather than a unique constraint.
    add_column :customers, :legacy_code, :string
    add_index :customers, %i[company_id legacy_code],
      where: "legacy_code IS NOT NULL AND legacy_code <> ''",
      name: "index_customers_on_company_id_and_legacy_code"
  end
end
