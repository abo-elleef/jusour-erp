# frozen_string_literal: true

# A print job used to mean "an order's ticket". The drawer closing slip is not
# about an order, so a job may now belong to a cash drawer session instead.
# workstation_id says which register should print it (receipts get theirs from the
# order; a drawer has none of its own).
class LetPrintLogsBelongToADrawer < ActiveRecord::Migration[7.1]
  def change
    change_column_null :print_logs, :order_id, true
    add_reference :print_logs, :cash_drawer_session, type: :uuid, foreign_key: true, index: true
    add_reference :print_logs, :workstation, type: :uuid, foreign_key: true, index: true
  end
end
