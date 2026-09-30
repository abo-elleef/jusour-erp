class AddPartyToExpensesAndIncomes < ActiveRecord::Migration[7.1]
  def change
    add_reference :expenses, :party, polymorphic: true, type: :uuid
    add_reference :incomes, :party, polymorphic: true, type: :uuid
  end
end
