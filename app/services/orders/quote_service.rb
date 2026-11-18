# frozen_string_literal: true

module Orders
  # Prices a cart without saving anything, with the same rules the POS uses
  # (Orders::ResolveLine, strict). Used by public self-ordering for the checkout
  # preview and for the price snapshot kept on the request.
  #
  #   Orders::QuoteService.call(location:, items: [{ "menu_item_id" => ..., "modifier_ids" => [...],
  #                                                  "quantity" => 2, "notes" => "" }],
  #                             delivery_fee_cents: 2000)
  #
  # Lines that can't be priced are reported in #errors (by index) and left out of the
  # totals, so the caller decides whether to refuse the whole cart.
  class QuoteService
    MAX_LINES = 50

    Result = Struct.new(:lines, :errors, :subtotal_cents, :discount_cents, :delivery_fee_cents,
                        keyword_init: true) do
      def total_cents = subtotal_cents - discount_cents + delivery_fee_cents
      def ok? = errors.empty? && lines.any?

      # What gets stored on the request and shown back to the customer.
      def snapshot
        {
          "lines" => lines.map do |line|
            {
              "menu_item_id" => line.menu_item&.id, "combo_id" => line.combo&.id, "name" => line.name,
              "modifiers" => line.modifiers.map { |m| { "id" => m.id, "name" => m.name,
                                                        "price_cents" => m.price_adjustment_cents } },
              "quantity" => line.quantity, "notes" => line.notes,
              "unit_price_cents" => line.unit_price_cents, "line_total_cents" => line.line_total_cents,
              "discount_cents" => line.discount_cents
            }
          end,
          "subtotal_cents" => subtotal_cents, "discount_cents" => discount_cents,
          "delivery_fee_cents" => delivery_fee_cents, "total_cents" => total_cents
        }
      end
    end

    def self.call(...)
      new(...).call
    end

    def initialize(location:, items:, delivery_fee_cents: 0)
      @location = location
      @items = Array(items).first(MAX_LINES)
      @delivery_fee_cents = delivery_fee_cents.to_i
    end

    def call
      promo_finder = Menus::ActivePromo.new(location: @location)
      lines = []
      errors = {}
      @items.each_with_index do |raw, index|
        raw = raw.to_h.stringify_keys
        lines << ResolveLine.call(
          location: @location, strict: true, promo_finder: promo_finder, channel: :public,
          menu_item_id: raw["menu_item_id"], combo_id: raw["combo_id"],
          modifier_ids: raw["modifier_ids"], quantity: raw["quantity"], notes: raw["notes"]
        )
      rescue ResolveLine::Invalid => e
        errors[index] = e.code
      end

      Result.new(
        lines: lines, errors: errors,
        subtotal_cents: lines.sum(&:line_total_cents),
        discount_cents: lines.sum(&:discount_cents),
        delivery_fee_cents: @delivery_fee_cents
      )
    end
  end
end
