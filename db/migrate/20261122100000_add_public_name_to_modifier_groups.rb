# frozen_string_literal: true

# The name customers see on the public menu. Blank means "use the cashier name".
class AddPublicNameToModifierGroups < ActiveRecord::Migration[7.1]
  def change
    add_column :modifier_groups, :public_name, :string
  end
end
