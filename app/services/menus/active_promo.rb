# frozen_string_literal: true

module Menus
  class ActivePromo
    Result = Struct.new(
      :promo,
      :list_price_cents,
      :promo_price_cents,
      :discount_cents,
      :highlight,
      :label,
      keyword_init: true
    )

    def self.for(menu_item:, location:, at: Time.current)
      new(location: location, at: at).for_item(menu_item)
    end

    def self.index_for(menu_items:, location:, at: Time.current)
      new(location: location, at: at).index_for(menu_items)
    end

    def initialize(location:, at: Time.current)
      @location = location
      @at = at
    end

    def for_item(menu_item)
      return if menu_item.blank? || @location.blank?

      promo = candidates.find { |row| row.menu_item_id == menu_item.id }
      build_result(menu_item, promo)
    end

    def index_for(menu_items)
      items = Array(menu_items)
      return {} if items.empty? || @location.blank?

      by_item_id = candidates.index_by(&:menu_item_id)
      items.each_with_object({}) do |item, map|
        result = build_result(item, by_item_id[item.id])
        map[item.id] = result if result
      end
    end

    private

    def candidates
      @candidates ||= MenuPromo.active_at(@at)
        .for_location(@location)
        .includes(:menu_item)
        .order(Arel.sql("CASE WHEN location_id IS NULL THEN 1 ELSE 0 END"), :promo_price_cents)
        .to_a
        .uniq(&:menu_item_id)
    end

    def build_result(menu_item, promo)
      return if promo.blank?

      list = menu_item.price_cents_at(@location)
      discount = [list - promo.promo_price_cents, 0].max
      return if discount <= 0

      Result.new(
        promo: promo,
        list_price_cents: list,
        promo_price_cents: promo.promo_price_cents,
        discount_cents: discount,
        highlight: promo.highlight?,
        label: promo.name
      )
    end
  end
end
