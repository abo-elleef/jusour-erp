# frozen_string_literal: true

# What the public menu's order popup needs to know about an item. Prices here are
# only labels for the customer; the server re-prices everything (Orders::QuoteService).
module PublicOrderingHelper
  # pricing: the same config the POS customize modal uses (PosModifierHelper), so
  # the popup shows the whole item price beside every choice ("110.00", not
  # "+35.00") and keeps the header price in step with what is picked, promo
  # included. The checkout total still comes from the server's quote.
  def orderable_item_json(item, location)
    groups = item.modifier_groups.to_a
    {
      kind: "menu_item", id: item.id, name: item.name,
      price: format_money(item.price_cents_at(location)),
      pricing: modifier_pricing_config(item, location, groups, active_promo: public_menu_active_promo(location)),
      groups: groups.map do |group|
        {
          id: group.id, name: group.display_name_for_public, required: group.required, multi: group.multi_select,
          max: group.max_selections,
          modifiers: group.modifiers.map { |mod| { id: mod.id, name: mod.name } }
        }
      end
    }.to_json
  end

  # One promo lookup per page and branch, shared by every card's item JSON.
  def public_menu_active_promo(location)
    (@public_menu_active_promos ||= {})[location.id] ||= Menus::ActivePromo.new(location: location)
  end

  # The public menu card is the tap target when the branch takes online orders
  # (no separate Add button, like the POS register). Keyboard users get it too.
  def public_menu_card_tap_class
    " cursor-pointer select-none transition hover:border-amber-400 hover:shadow-md active:scale-[0.99] " \
      "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-700/40"
  end

  def public_menu_card_tap_attributes(item_json)
    tag.attributes(
      role: "button", tabindex: 0,
      data: { item: item_json,
              action: "click->online-order#open keydown.enter->online-order#open:prevent keydown.space->online-order#open:prevent" }
    )
  end

  # localStorage key for the orders this browser sent to one branch
  # (see recent_orders_controller.js). Shared by the menu and the status page.
  def recent_orders_storage_key(company, location)
    "online-orders:#{company.slug}:#{location.slug}"
  end

  def orderable_combo_json(combo)
    { kind: "combo", id: combo.id, name: combo.name, price: format_money(combo.price_cents), groups: [] }.to_json
  end
end
