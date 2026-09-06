# frozen_string_literal: true

# Traceability + idempotency for sales history imported from the previous system:
# the old document number is kept on the record, so a re-run updates instead of
# duplicating and staff can tie a row back to the old system.
class AddLegacyNumberToSalesDocuments < ActiveRecord::Migration[7.1]
  def change
    add_column :customer_invoices, :legacy_number, :string
    add_column :credit_notes, :legacy_number, :string

    add_index :customer_invoices, %i[company_id legacy_number],
      unique: true, where: "legacy_number IS NOT NULL",
      name: "index_customer_invoices_on_company_id_and_legacy_number"
    add_index :credit_notes, %i[company_id legacy_number],
      unique: true, where: "legacy_number IS NOT NULL",
      name: "index_credit_notes_on_company_id_and_legacy_number"
  end
end
