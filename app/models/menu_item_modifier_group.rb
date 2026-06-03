# frozen_string_literal: true

class MenuItemModifierGroup < ApplicationRecord
  belongs_to :menu_item
  belongs_to :modifier_group

  validates :modifier_group_id, uniqueness: { scope: :menu_item_id }
end
