# frozen_string_literal: true

class MenuItemModifierGroup < ApplicationRecord
  belongs_to :menu_item
  belongs_to :modifier_group

  validates :modifier_group_id, uniqueness: { scope: :menu_item_id }
  validate :matrix_group_is_single_choice

  # The combination recipes are keyed on the ticked groups' options, so a
  # change to which groups are ticked leaves them describing combinations that
  # no longer exist: start the item's matrix over.
  after_commit :clear_combination_recipes, on: %i[update destroy], if: :matrix_changed?

  private

  # A multi-select group would need a row per subset of its options; those
  # groups stay add-on-top.
  def matrix_group_is_single_choice
    errors.add(:recipe_matrix, :single_choice_only) if recipe_matrix && modifier_group&.multi_select
  end

  def matrix_changed?
    destroyed? ? recipe_matrix : saved_change_to_recipe_matrix?
  end

  def clear_combination_recipes
    CombinationRecipe.unscoped.where(menu_item_id: menu_item_id).destroy_all
  end
end
