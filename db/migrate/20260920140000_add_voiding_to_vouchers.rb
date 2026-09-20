# frozen_string_literal: true

# A voucher is never deleted. It is voided, and it stays in the book.
#
# Editing an expense used to destroy the voucher that paid it and issue a new
# one. That left the numbered book in two different broken states: deleting the
# highest voucher let the next one REUSE its number, so a document already
# printed and handed to a supplier could be reissued at a different amount under
# the same number; deleting an older one left an unexplained gap, which an
# auditor cannot tell from a lost document.
#
# Keeping the row fixes both. The number is never handed out twice because the
# voided row still counts, and the gap in the sequence is explained by a visible
# voided document rather than by nothing at all.
class AddVoidingToVouchers < ActiveRecord::Migration[7.1]
  def change
    add_column :vouchers, :voided_at, :datetime
    add_column :vouchers, :voided_reason, :string
    add_column :vouchers, :voided_by_id, :uuid
    # The voucher issued in its place, when it was voided because the record it
    # settled changed rather than because it was wrong.
    add_column :vouchers, :replaced_by_id, :uuid

    add_index :vouchers, :voided_at
    add_index :vouchers, :replaced_by_id
    add_foreign_key :vouchers, :users, column: :voided_by_id
    add_foreign_key :vouchers, :vouchers, column: :replaced_by_id
  end
end
