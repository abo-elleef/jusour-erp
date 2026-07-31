# frozen_string_literal: true

class RemoveShiftFromCashDrawerSessions < ActiveRecord::Migration[7.1]
  def change
    remove_column :cash_drawer_sessions, :shift, :string, null: false
  end
end
