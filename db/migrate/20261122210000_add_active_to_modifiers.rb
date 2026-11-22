# frozen_string_literal: true

# An option that has been ordered can't be deleted (past orders point at it), so
# the admin hides it instead. Inactive options stay on old orders and reports.
class AddActiveToModifiers < ActiveRecord::Migration[7.1]
  def change
    add_column :modifiers, :active, :boolean, default: true, null: false
  end
end
