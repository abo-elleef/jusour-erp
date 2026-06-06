# frozen_string_literal: true

class StaffPayroll < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :monthly_salary_cents, :integer, default: 0, null: false

    create_table :payroll_adjustments, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.references :recorded_by, null: false, foreign_key: { to_table: :users }, type: :uuid
      t.string :kind, null: false
      t.string :unit_type, null: false
      t.integer :amount_cents, null: false
      t.date :payroll_month, null: false
      t.text :notes

      t.timestamps
    end

    add_index :payroll_adjustments, %i[user_id payroll_month]
    add_index :payroll_adjustments, :payroll_month
  end
end
