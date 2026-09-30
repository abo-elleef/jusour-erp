class AddInstallmentsTotalToLoans < ActiveRecord::Migration[7.1]
  def change
    add_column :loans, :installments_total, :integer
  end
end
