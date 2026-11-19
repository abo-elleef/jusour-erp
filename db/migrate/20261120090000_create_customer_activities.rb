# frozen_string_literal: true

# A customer's own timeline (calls, notes, meetings) — the twin of
# lead_activities for after a lead becomes a customer (Bazzar slice F).
class CreateCustomerActivities < ActiveRecord::Migration[7.1]
  def change
    create_table :customer_activities, id: :uuid do |t|
      t.references :customer, type: :uuid, null: false, foreign_key: true
      t.references :user, type: :uuid, null: true, foreign_key: true

      t.string   :activity_type, null: false
      t.text     :note
      t.datetime :occurred_at, null: false

      t.timestamps
    end
    add_index :customer_activities, %i[customer_id occurred_at]
  end
end
