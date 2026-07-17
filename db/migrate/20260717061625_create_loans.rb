class CreateLoans < ActiveRecord::Migration[7.1]
  def change
    create_table :loans, id: :uuid do |t|
      t.references :company,        null: false, foreign_key: true, type: :uuid
      t.string  :name,              null: false
      t.string  :loan_type,         null: false, default: "bank_loan"
      t.integer :account_code,      null: false
      t.bigint  :principal_cents,   null: false, default: 0
      t.decimal :interest_rate,     precision: 5, scale: 2, default: 0
      t.date    :disbursement_date
      t.date    :due_date
      t.boolean :active,            null: false, default: true
      t.text    :notes
      t.timestamps
    end

    add_index :loans, [ :company_id, :account_code ], unique: true
  end
end
