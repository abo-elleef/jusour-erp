# frozen_string_literal: true

class AddUserActiveAndPin < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :active, :boolean, null: false, default: true
    add_column :users, :pin_digest, :string
    add_index :users, :active
  end
end
