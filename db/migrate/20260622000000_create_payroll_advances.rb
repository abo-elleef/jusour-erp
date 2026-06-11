# frozen_string_literal: true

class CreatePayrollAdvances < ActiveRecord::Migration[7.1]
  def change
    create_table :payroll_advances, id: :uuid do |t|
      t.references :company, null: false, foreign_key: true, type: :uuid
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.references :treasury, null: false, foreign_key: true, type: :uuid
      t.references :paid_by, null: false, foreign_key: { to_table: :users }, type: :uuid
      t.date :payroll_month, null: false
      t.string :advance_slot, null: false
      t.date :paid_on, null: false
      t.integer :amount_cents, null: false
      t.text :notes

      t.timestamps
    end

    add_index :payroll_advances, %i[user_id payroll_month advance_slot], unique: true,
      name: "index_payroll_advances_on_user_month_and_slot"
    add_index :payroll_advances, :payroll_month

    add_column :payroll_snapshots, :advances_cents, :integer, default: 0, null: false
    add_column :payroll_snapshots, :remaining_pay_cents, :integer, default: 0, null: false
  end
end
