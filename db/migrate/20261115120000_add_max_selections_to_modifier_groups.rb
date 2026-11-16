# frozen_string_literal: true

# Optional cap on a multi-select group: "pick up to 3 sauces". Nil = no cap.
class AddMaxSelectionsToModifierGroups < ActiveRecord::Migration[7.1]
  def change
    add_column :modifier_groups, :max_selections, :integer
  end
end
