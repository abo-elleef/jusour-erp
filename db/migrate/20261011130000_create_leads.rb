# frozen_string_literal: true

# A prospect in the distribution sales funnel, before they've made their first
# purchase. Converting creates a real Customer (see Lead#convert!) — leads never
# carry AR/billing state themselves, only pipeline state.
class CreateLeads < ActiveRecord::Migration[7.1]
  def change
    create_table :leads, id: :uuid do |t|
      t.references :company,       type: :uuid, null: false, index: true
      t.references :location,      type: :uuid, null: true, index: true
      t.references :assigned_user, type: :uuid, null: false, index: true
      t.references :created_by,    type: :uuid, null: false, index: true
      t.references :customer,      type: :uuid, null: true, index: true

      t.string   :name, null: false
      t.string   :phone
      t.string   :phone_secondary
      t.string   :email
      t.string   :source
      t.string   :stage, default: "new", null: false
      t.string   :lost_reason
      t.text     :lost_reason_note
      t.date     :next_follow_up_at
      t.datetime :converted_at
      t.datetime :lost_at
      t.text     :notes

      t.timestamps
    end

    add_index :leads, %i[company_id stage]
  end
end
