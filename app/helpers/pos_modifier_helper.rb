# frozen_string_literal: true

# Data for the POS "customize" modal's live prices (modifier_pricing_controller).
# The offline register builds the same shape from its snapshot.
module PosModifierHelper
  # active_promo: pass one Menus::ActivePromo when building many items on a page
  # (the public menu), so the live promos are loaded once, not once per item.
  def modifier_pricing_config(menu_item, location, groups, active_promo: nil)
    active_promo ||= Menus::ActivePromo.new(location: location)
    promos = active_promo.all_for_item(menu_item)
    {
      base_cents: menu_item.price_cents_at(location),
      groups: groups.map do |group|
        {
          id: group.id,
          multi_select: group.multi_select ? true : false,
          max_selections: group.max_selections,
          modifiers: group.available_modifiers.map { |m| { id: m.id, price_adjustment_cents: m.price_adjustment_cents } }
        }
      end,
      promos: promos.map { |row| { modifier_id: row.modifier_id, discount_cents: row.discount_cents } }
    }
  end

  # Same rule as groupShowsPrices in utils/modifier_pricing.js.
  def modifier_group_shows_prices?(group, config)
    targeted = config[:promos].filter_map { |row| row[:modifier_id] }
    group.available_modifiers.any? { |m| m.price_adjustment_cents != 0 || targeted.include?(m.id) }
  end
end
