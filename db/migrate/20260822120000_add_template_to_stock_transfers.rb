# frozen_string_literal: true

# Records which template a transfer was built from. Previously the template was
# only a transient param on the new form, so once saved the transfer had no memory
# of it — which means a unit rule based on "came from a template" could not survive
# an edit.
#
# Nullify rather than cascade: deleting a template must not delete transfers, and a
# transfer whose template is gone is still a valid record (it just stops being
# unit-locked).
class AddTemplateToStockTransfers < ActiveRecord::Migration[7.1]
  def change
    add_reference :stock_transfers, :stock_transfer_template,
      type: :uuid, null: true, index: true,
      foreign_key: { on_delete: :nullify }
  end
end
