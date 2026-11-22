# frozen_string_literal: true

class Modifier < ApplicationRecord
  include Tenantable
  include MoneyInputs

  money_input :price_adjustment_cents

  belongs_to :modifier_group
  has_many :order_item_modifiers, dependent: :restrict_with_error
  has_many :modifier_recipes, dependent: :destroy
  has_many :menu_promos, dependent: :destroy
  has_many :ingredients, through: :modifier_recipes

  monetize :price_adjustment_cents, allow_nil: false

  validates :name, presence: true

  # Inactive: hidden from the POS, the offline register, the public menu and the
  # call center, and refused on new lines. Old orders still point at it, which is
  # why an ordered option is deactivated rather than deleted.
  scope :active, -> { where(active: true) }
  validates :price_adjustment_cents, numericality: { only_integer: true }

  private

  def assign_company
    self.company ||= modifier_group&.company || Current.company
  end
end
