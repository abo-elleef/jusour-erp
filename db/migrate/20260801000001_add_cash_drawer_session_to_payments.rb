# frozen_string_literal: true

class AddCashDrawerSessionToPayments < ActiveRecord::Migration[7.1]
  def change
    add_reference :payments, :cash_drawer_session, type: :uuid, null: true, foreign_key: true, index: true
  end
end
