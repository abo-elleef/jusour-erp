# frozen_string_literal: true

class OrderItem < ApplicationRecord
  include Priceable

  belongs_to :order
  belongs_to :menu_item, optional: true
  belongs_to :combo, optional: true
  has_many :order_item_modifiers, dependent: :destroy

  monetize :unit_price_cents

  validates :quantity, numericality: { greater_than: 0, only_integer: true }
  validate :menu_item_or_combo_present

  def display_name
    combo&.name || menu_item&.name
  end

  def modifier_total_cents
    order_item_modifiers.sum(:price_adjustment_cents)
  end

  def tax_category
    menu_item&.tax_category || "food"
  end

  private

  def menu_item_or_combo_present
    return if menu_item_id.present? ^ combo_id.present?

    errors.add(:base, "must belong to either a menu item or a combo")
  end
end
