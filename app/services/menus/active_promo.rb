# frozen_string_literal: true

module Menus
  # Finds the live promo for a menu item at a branch.
  #
  # A promo either covers the whole item (modifier_id blank) or one choice of
  # it (e.g. only the "Double" size). When several could apply, the first in
  # this order wins — the offline POS relies on the same order, see
  # Orders::OfflineSnapshotService:
  #   1. choice-specific before whole-item (the more specific rule)
  #   2. branch-specific before all-branches
  #   3. lowest promo price
  class ActivePromo
    Result = Struct.new(
      :promo,
      :list_price_cents,
      :promo_price_cents,
      :discount_cents,
      :highlight,
      :label,
      :modifier_id,
      :modifier_name,
      keyword_init: true
    )

    # The promo for one order line, given the choices on it.
    def self.for(menu_item:, location:, modifier_ids: [], at: Time.current)
      new(location: location, at: at).for_item(menu_item, modifier_ids: modifier_ids)
    end

    # One promo per item for menu cards: a whole-item promo if there is one,
    # otherwise the first choice-specific one.
    def self.index_for(menu_items:, location:, at: Time.current)
      new(location: location, at: at).index_for(menu_items)
    end

    def initialize(location:, at: Time.current)
      @location = location
      @at = at
    end

    def for_item(menu_item, modifier_ids: [])
      return if menu_item.blank? || @location.blank?

      chosen = Array(modifier_ids).compact
      all_for_item(menu_item).find { |result| result.modifier_id.nil? || chosen.include?(result.modifier_id) }
    end

    def index_for(menu_items)
      items = Array(menu_items)
      return {} if items.empty? || @location.blank?

      items.each_with_object({}) do |item, map|
        results = all_for_item(item)
        result = results.find { |row| row.modifier_id.nil? } || results.first
        map[item.id] = result if result
      end
    end

    # Every applicable promo for the item, in priority order.
    def all_for_item(menu_item)
      return [] if menu_item.blank? || @location.blank?

      candidates_by_item_id.fetch(menu_item.id, [])
        .uniq(&:modifier_id)
        .filter_map { |promo| build_result(menu_item, promo) }
    end

    private

    def candidates_by_item_id
      @candidates_by_item_id ||= MenuPromo.active_at(@at)
        .for_location(@location)
        .includes(:modifier)
        .order(
          Arel.sql("CASE WHEN menu_promos.modifier_id IS NULL THEN 1 ELSE 0 END"),
          Arel.sql("CASE WHEN menu_promos.location_id IS NULL THEN 1 ELSE 0 END"),
          :promo_price_cents
        )
        .to_a
        .group_by(&:menu_item_id)
    end

    def build_result(menu_item, promo)
      return if promo.blank?

      list = menu_item.price_cents_at(@location) + promo.modifier_adjustment_cents
      discount = [list - promo.promo_price_cents, 0].max
      return if discount <= 0

      Result.new(
        promo: promo,
        list_price_cents: list,
        promo_price_cents: promo.promo_price_cents,
        discount_cents: discount,
        highlight: promo.highlight?,
        label: promo.name,
        modifier_id: promo.modifier_id,
        modifier_name: promo.modifier&.name
      )
    end
  end
end
