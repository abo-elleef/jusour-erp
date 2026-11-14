# frozen_string_literal: true

module Orders
  # Puts a resolved line (Orders::ResolveLine) on an order. The same item with the
  # same choices and no note is the same line: the count goes up instead of
  # stacking identical rows. Returns the order item.
  #
  # The caller holds the order lock and recalculates totals afterwards.
  class AddLineService
    def self.call(order:, line:)
      new(order:, line:).call
    end

    def initialize(order:, line:)
      @order = order
      @line = line
    end

    def call
      @line.combo ? add_combo : add_menu_item
    end

    private

    def add_combo
      existing = @order.order_items.find_by(combo_id: @line.combo.id, unit_price_cents: @line.unit_price_cents,
                                            notes: [nil, ""])
      if existing && @line.notes.blank?
        existing.update!(quantity: existing.quantity + @line.quantity)
        return existing
      end

      @order.order_items.create!(combo: @line.combo, quantity: @line.quantity,
                                 unit_price_cents: @line.unit_price_cents, notes: @line.notes)
    end

    def add_menu_item
      if @line.notes.blank? && (existing = same_line)
        existing.update!(quantity: existing.quantity + @line.quantity)
        Promos::SyncOrderItemDiscount.call(order_item: existing)
        return existing
      end

      item = @order.order_items.create!(
        menu_item: @line.menu_item,
        quantity: @line.quantity,
        unit_price_cents: @line.unit_price_cents,
        notes: @line.notes
      )
      @line.modifiers.each do |mod|
        item.order_item_modifiers.create!(modifier: mod, name: mod.name,
                                          price_adjustment_cents: mod.price_adjustment_cents)
      end
      Promos::SyncOrderItemDiscount.call(order_item: item)
      item
    end

    def same_line
      wanted = @line.modifier_ids
      @order.order_items.includes(:order_item_modifiers)
            .where(menu_item_id: @line.menu_item.id, unit_price_cents: @line.unit_price_cents, notes: [nil, ""])
            .detect { |row| row.order_item_modifiers.map(&:modifier_id).compact.sort == wanted }
    end
  end
end
