# frozen_string_literal: true

# What one combination of options uses — "Double · Spicy: beef 0.2 kg, bun 1,
# hot sauce 0.04 kg" — as a full recipe, not a difference. Keyed by the chosen
# options of the menu item's ticked groups (MenuItemModifierGroup#recipe_matrix),
# sorted. When a sold line's combination has one, it is used in place of the
# item recipe and those options' own recipes (Inventory::LineConsumption).
class CombinationRecipe < ApplicationRecord
  include Tenantable

  belongs_to :menu_item
  has_many :lines, -> { order(:created_at) }, class_name: "CombinationRecipeLine", dependent: :destroy

  before_validation { self.modifier_ids = Array(modifier_ids).compact.map(&:to_s).uniq.sort }
  validates :modifier_ids, uniqueness: { scope: :menu_item_id }

  def self.key_for(modifier_ids)
    Array(modifier_ids).compact.map(&:to_s).uniq.sort
  end

  def modifiers
    Modifier.where(id: modifier_ids)
  end

  private

  def assign_company
    self.company ||= menu_item&.company || Current.company
  end
end
