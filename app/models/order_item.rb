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
  # kitchen/station/pick tickets and the receipt — lists them in this one order, the
  # same as the register's category rail: offers first (lines that got a menu promo,
  # and highlighted combos), then the menu categories in the menu's own order
  # (position, then name), then the other combos. A→Z by name inside each group; two
  # lines of the same item (different modifiers) keep the order they were added in.
  # The offline register sorts its cart the same way (sortCartLines in
  # offline_pos_controller.js). Preload :order_discounts and menu_item: :category.
  def self.in_menu_order(items)
    items.sort_by(&:menu_sort_key)
  end

  # On offer as the register shows it: a menu promo priced this line (a promo can
  # target one choice, so a Single may be on offer while a Double is not), or the
  # combo is highlighted right now.
  def offer_line?
    return combo.highlighted_now? if combo

    order_discounts.any? { |discount| discount.menu_promo_id.present? }
  end

  def menu_sort_key
    category = menu_item&.category
    group = if offer_line? then 0
            elsif category then 1
            else 2
            end
    [
      group,
      group.zero? || category&.position.nil? ? 1 : 0,
      group.zero? ? 0 : category&.position.to_i,
      group.zero? ? "" : category&.name.to_s.downcase,
      display_name.to_s.downcase,
      created_at || Time.current,
      id.to_s
    ]
  end

  def display_name
    combo&.name || menu_item&.name
  end

  # Same number either way: when the modifiers are already loaded (the totals
  # preload them), add them up in Ruby instead of one SQL sum per line.
  def modifier_total_cents
    if order_item_modifiers.loaded?
      order_item_modifiers.sum(&:price_adjustment_cents)
    else
      order_item_modifiers.sum(:price_adjustment_cents)
    end
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
