# frozen_string_literal: true

module Printing
  class OrderItemRouting
    def self.menu_item_ids_for(order_item)
      if order_item.menu_item_id.present?
        [order_item.menu_item_id]
      elsif order_item.combo_id.present?
        ComboItem.where(combo_id: order_item.combo_id).pluck(:menu_item_id)
      else
        []
      end
    end

    def self.matching_items(order_items, printer)
      assigned_ids = printer.menu_item_ids
      return [] if assigned_ids.empty?

      order_items.select do |item|
        menu_item_ids_for(item).any? { |id| assigned_ids.include?(id) }
      end
    end
  end
end
