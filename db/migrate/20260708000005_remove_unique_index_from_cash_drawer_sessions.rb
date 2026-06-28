# frozen_string_literal: true

class RemoveUniqueIndexFromCashDrawerSessions < ActiveRecord::Migration[7.1]
  def change
    remove_index :cash_drawer_sessions,
                 column: %i[user_id session_date shift],
                 name: "idx_on_user_id_session_date_shift_04dd8c9892",
                 unique: true
  end
end
