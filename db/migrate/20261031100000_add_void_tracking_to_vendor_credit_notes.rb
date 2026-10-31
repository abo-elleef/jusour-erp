# frozen_string_literal: true

# Voiding a confirmed credit note has to put its returned stock back, so each
# stock movement now records the credit note that made it instead of leaving
# only a localized sentence in reason_notes. The backfill matches the existing
# rows on that sentence — the credit note number followed by a non-digit — and
# on the line's ingredient and the note's location, in raw SQL so it does not
# depend on today's models.
class AddVoidTrackingToVendorCreditNotes < ActiveRecord::Migration[7.1]
  def up
    add_reference :stock_adjustments, :vendor_credit_note, type: :uuid, foreign_key: true, index: true
    add_column :vendor_credit_notes, :voided_at, :datetime
    add_reference :vendor_credit_notes, :voided_by, type: :uuid, foreign_key: { to_table: :users }

    execute <<~SQL
      UPDATE stock_adjustments sa
      SET vendor_credit_note_id = vcn.id
      FROM vendor_credit_notes vcn
      WHERE sa.adjustment_type = 'vendor_credit_note'
        AND sa.vendor_credit_note_id IS NULL
        AND vcn.status = 'confirmed'
        AND vcn.kind = 'goods_return'
        AND sa.location_id = vcn.location_id
        AND sa.reason_notes ~ (vcn.credit_note_number || '([^0-9]|$)')
        AND EXISTS (
          SELECT 1 FROM vendor_credit_note_lines l
          WHERE l.vendor_credit_note_id = vcn.id AND l.ingredient_id = sa.ingredient_id
        )
    SQL
  end

  def down
    remove_reference :vendor_credit_notes, :voided_by, foreign_key: { to_table: :users }
    remove_column :vendor_credit_notes, :voided_at
    remove_reference :stock_adjustments, :vendor_credit_note, foreign_key: true, index: true
  end
end
