# frozen_string_literal: true

# Branches that seat customers (a cafe) keep a table's order open while they eat and
# pay at the end. Off by default: every other branch stays pay-first.
class AddTableServiceToLocations < ActiveRecord::Migration[7.1]
  def change
    add_column :locations, :table_service, :boolean, default: false, null: false
  end
end
