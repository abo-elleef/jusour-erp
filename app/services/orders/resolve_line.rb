# frozen_string_literal: true

module Orders
  # Turns "what the customer or cashier asked for" (an item or combo id, choice ids,
  # a count, a note) into a priced line, using only prices from the database.
  #
  # Shared by the POS cart (Orders::AddLineService) and the public self-order quote
  # (Orders::QuoteService), so the two can never price the same line differently.
  #
  # Choices that don't belong to the item are always dropped. With strict: true it also
  # refuses a line whose required groups are empty, whose single-choice group has
  # more than one pick, or whose multi-select group goes over its max_selections — the public menu has no cashier to catch that. The POS modal
  # already enforces both in the browser, so the POS runs non-strict.
  class ResolveLine
    class Invalid < StandardError
      attr_reader :code

      def initialize(code, message = nil)
        @code = code
        super(message || code.to_s)
      end
    end

    Line = Struct.new(
      :menu_item, :combo, :modifiers, :quantity, :notes,
      :unit_price_cents, :promo, keyword_init: true
    ) do
      def modifier_ids = modifiers.map(&:id).sort
      def modifier_total_cents = modifiers.sum(&:price_adjustment_cents)
      def line_total_cents = (unit_price_cents + modifier_total_cents) * quantity
      def discount_cents = promo && promo.discount_cents.positive? ? promo.discount_cents * quantity : 0
      def name = menu_item&.name || combo&.name
    end

    MAX_QUANTITY = 99

    def self.call(...)
      new(...).call
    end

    def initialize(location:, menu_item_id: nil, combo_id: nil, modifier_ids: [], quantity: 1, notes: nil,
                   strict: false, promo_finder: nil)
      @location = location
      @menu_item_id = menu_item_id.presence
      @combo_id = combo_id.presence
      @modifier_ids = Array(modifier_ids).map(&:to_s).reject(&:blank?).uniq
      @quantity = quantity.to_i
      @notes = notes.to_s.strip.presence
      @strict = strict
      @promo_finder = promo_finder || Menus::ActivePromo.new(location: location)
    end

    def call
      @quantity = 1 unless @quantity.positive?
      raise Invalid, :bad_quantity if @strict && @quantity > MAX_QUANTITY

      @combo_id ? resolve_combo : resolve_menu_item
    end

    private

    def resolve_combo
      combo = Combo.available_at_location(@location).find_by(id: @combo_id)
      raise Invalid, :unavailable if combo.nil?

      Line.new(combo: combo, modifiers: [], quantity: @quantity, notes: @notes,
               unit_price_cents: combo.price_cents, promo: nil)
    end

    def resolve_menu_item
      menu_item = MenuItem.includes(:location_menu_items, menu_item_modifier_groups: :modifier_group)
                          .find_by(id: @menu_item_id)
      raise Invalid, :unavailable if menu_item.nil? || !menu_item.available_at_location?(@location)

      modifiers = allowed_modifiers(menu_item)
      check_groups!(menu_item, modifiers) if @strict

      Line.new(
        menu_item: menu_item,
        modifiers: modifiers,
        quantity: @quantity,
        notes: @notes,
        unit_price_cents: menu_item.price_cents_at(@location),
        promo: @promo_finder.for_item(menu_item, modifier_ids: modifiers.map(&:id))
      )
    end

    def allowed_modifiers(menu_item)
      return [] if @modifier_ids.empty?

      Modifier.where(id: @modifier_ids, modifier_group_id: menu_item.modifier_group_ids).to_a
    end

    def check_groups!(menu_item, modifiers)
      picked_by_group = modifiers.group_by(&:modifier_group_id)
      menu_item.menu_item_modifier_groups.map(&:modifier_group).each do |group|
        picks = picked_by_group.fetch(group.id, [])
        raise Invalid.new(:required_choice, group.name) if group.required && picks.empty?
        raise Invalid.new(:single_choice, group.name) if !group.multi_select && picks.size > 1
        raise Invalid.new(:too_many_choices, group.name) if group.max_selections && picks.size > group.max_selections
      end
    end
  end
end
