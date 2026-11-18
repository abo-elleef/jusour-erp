# frozen_string_literal: true

# Where a category's items are offered: both the POS register and the public
# menu (default), the POS only, or the public menu only.
class AddMenuVisibilityToCategories < ActiveRecord::Migration[7.1]
  def change
    add_column :categories, :menu_visibility, :string, null: false, default: "both"
    add_check_constraint :categories, "menu_visibility IN ('both', 'pos', 'public')",
      name: "categories_menu_visibility_check"
  end
end
