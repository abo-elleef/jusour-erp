# frozen_string_literal: true

class OrderItem < ApplicationRecord
  include Priceable

  belongs_to :order
  belongs_to :menu_item, optional: true
  belongs_to :combo, optional: true
  has_many :order_item_modifiers, dependent: :destroy
  has_many :order_discounts, dependent: :destroy

  monetize :unit_price_cents

  validates :quantity, numericality: { greater_than: 0, only_integer: true }
  validate :menu_item_or_combo_present

  # Every place that lists an order's lines — the POS basket, the order pages, the
  # kitchen/station/pick tickets and the receipt — lists them in this one order:
  # grouped by menu category in the menu's own category order (position, then name),
  # A→Z by name inside each category, combos after all categories. Two lines of the
  # same item (different modifiers) keep the order they were added in.
  # The offline register sorts its cart the same way (sortCartLines in
  # offline_pos_controller.js). Preload menu_item: :category to avoid N+1.
  def self.in_menu_order(items)
    items.sort_by(&:menu_sort_key)
  end

  def menu_sort_key
    category = menu_item&.category
    [
      category ? 0 : 1,
      category&.position.nil? ? 1 : 0,
      category&.position.to_i,
      category&.name.to_s.downcase,
      display_name.to_s.downcase,
      created_at || Time.current,
      id.to_s
    ]
  end

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
