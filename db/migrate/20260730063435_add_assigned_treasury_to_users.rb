# frozen_string_literal: true

class AddAssignedTreasuryToUsers < ActiveRecord::Migration[7.1]
  def change
    add_reference :users, :assigned_treasury, type: :uuid, null: true,
                  foreign_key: { to_table: :treasuries, on_delete: :nullify },
                  index: true
  end
end
