# frozen_string_literal: true

# A vendor credit note is not always a goods return: a supplier rebate or a
# corrected price reduces AP while the goods stay on the shelf. `kind` tells the
# two apart, and only a goods return moves stock — which needs `location_id` to
# say which location the goods leave from.
#
# Every note written before this migration ran only ever reduced AP, so they are
# all backfilled as price adjustments. Nothing already confirmed moves stock
# retroactively.
class AddKindAndLocationToVendorCreditNotes < ActiveRecord::Migration[7.1]
  def up
    add_column :vendor_credit_notes, :kind, :string
    add_reference :vendor_credit_notes, :location, type: :uuid, null: true,
      foreign_key: true, index: true

    execute <<~SQL
      UPDATE vendor_credit_notes SET kind = 'price_adjustment' WHERE kind IS NULL
    SQL

    change_column_default :vendor_credit_notes, :kind, from: nil, to: "goods_return"
    change_column_null :vendor_credit_notes, :kind, false
    add_index :vendor_credit_notes, %i[company_id kind]
  end

  def down
    remove_index :vendor_credit_notes, %i[company_id kind]
    remove_reference :vendor_credit_notes, :location, foreign_key: true
    remove_column :vendor_credit_notes, :kind
  end
end
