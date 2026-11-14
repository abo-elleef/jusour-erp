# frozen_string_literal: true

# What the public menu's order popup needs to know about an item. Prices here are
# only labels for the customer; the server re-prices everything (Orders::QuoteService).
module PublicOrderingHelper
  def orderable_item_json(item, location)
    {
      kind: "menu_item", id: item.id, name: item.name,
      price: format_money(item.price_cents_at(location)),
      groups: item.modifier_groups.map do |group|
        {
          id: group.id, name: group.name, required: group.required, multi: group.multi_select,
          modifiers: group.modifiers.map do |mod|
            { id: mod.id, name: mod.name,
              price: mod.price_adjustment_cents.zero? ? nil : "+#{format_money(mod.price_adjustment_cents)}" }
          end
        }
      end
    }.to_json
  end

  def orderable_combo_json(combo)
    { kind: "combo", id: combo.id, name: combo.name, price: format_money(combo.price_cents), groups: [] }.to_json
  end
end
