# frozen_string_literal: true

class AddReversedAtToExpensesAndIncomes < ActiveRecord::Migration[7.1]
  def change
    add_column :expenses, :reversed_at, :datetime, null: true
    add_column :incomes,  :reversed_at, :datetime, null: true
    add_index  :expenses, :reversed_at
    add_index  :incomes,  :reversed_at
  end
end
