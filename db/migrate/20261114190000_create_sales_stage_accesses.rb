# frozen_string_literal: true

# Per role, per invoice stage: can its members see invoices at that stage, and
# are they notified when an invoice enters it? Configured by the owner as a
# role × stage grid. A role with no rows keeps today's behaviour: sees every
# stage, gets no stage notifications.
class CreateSalesStageAccesses < ActiveRecord::Migration[7.1]
  def change
    create_table :sales_stage_accesses, id: :uuid do |t|
      t.references :company, null: false, foreign_key: true, type: :uuid
      t.references :role, null: false, foreign_key: true, type: :uuid
      t.string :stage, null: false
      t.boolean :can_see, null: false, default: true
      t.boolean :notify, null: false, default: false

      t.timestamps
    end

    add_index :sales_stage_accesses, %i[role_id stage], unique: true
  end
end
