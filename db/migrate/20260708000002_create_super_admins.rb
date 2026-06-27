# frozen_string_literal: true

class CreateSuperAdmins < ActiveRecord::Migration[7.1]
  def change
    create_table :super_admin_users, id: :uuid do |t|
      t.string :name, null: false
      t.string :email, null: false, default: ""
      t.string :encrypted_password, null: false, default: ""
      t.datetime :remember_created_at
      t.timestamps
    end

    add_index :super_admin_users, :email, unique: true
  end
end
