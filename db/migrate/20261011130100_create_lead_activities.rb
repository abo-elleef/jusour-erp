# frozen_string_literal: true

# The rep-authored timeline for a lead (calls, notes, stage/assignment changes).
# Kept separate from the `audited` field-level history on Lead itself — this is
# "what someone did", not a diff.
class CreateLeadActivities < ActiveRecord::Migration[7.1]
  def change
    create_table :lead_activities, id: :uuid do |t|
      t.references :lead, type: :uuid, null: false, index: true
      t.references :user, type: :uuid, null: true, index: true

      t.string   :activity_type, null: false
      t.text     :note
      t.datetime :occurred_at, null: false

      t.timestamps
    end
  end
end
