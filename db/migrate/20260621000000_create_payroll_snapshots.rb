# frozen_string_literal: true

class CreatePayrollSnapshots < ActiveRecord::Migration[7.1]
  def change
    create_table :payroll_snapshots, id: :uuid do |t|
      t.references :company, null: false, foreign_key: true, type: :uuid
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.references :finalized_by, null: false, foreign_key: { to_table: :users }, type: :uuid
      t.date :payroll_month, null: false
      t.integer :base_salary_cents, null: false, default: 0
      t.integer :daily_rate_cents, null: false, default: 0
      t.integer :penalties_cents, null: false, default: 0
      t.integer :bonuses_cents, null: false, default: 0
      t.integer :net_pay_cents, null: false, default: 0
      t.datetime :finalized_at, null: false

      t.timestamps
    end

    add_index :payroll_snapshots, %i[user_id payroll_month], unique: true
    add_index :payroll_snapshots, %i[company_id payroll_month]
  end
end
