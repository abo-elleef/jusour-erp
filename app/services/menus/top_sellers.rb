# frozen_string_literal: true

module Menus
  # The menu items this branch sold most over the last two weeks, best first, for
  # the "Most sold" row (see Menus::TopSellerRow). Counts units (quantity), only from
  # completed orders: drafts, open and cancelled orders are left out on purpose.
  # Combos are not counted. Cached for an hour per branch, so the register does
  # not run the sum on every page load.
  class TopSellers
    WINDOW = 14.days
    CACHE_TTL = 1.hour

    def self.call(location:, limit: 10)
      new(location:, limit:).call
    end

    def initialize(location:, limit:)
      @location = location
      @limit = limit
    end

    # Menu item ids, most sold first.
    def call
      return [] if @location.blank?

      Rails.cache.fetch(["menus/top_sellers", @location.id, @limit, Date.current], expires_in: CACHE_TTL) do
        OrderItem.joins(:order)
                 .where(orders: { location_id: @location.id, status: "completed", placed_at: WINDOW.ago.. })
                 .where.not(menu_item_id: nil)
                 .group(:menu_item_id)
                 .order(Arel.sql("SUM(order_items.quantity) DESC"), :menu_item_id)
                 .limit(@limit)
                 .pluck(:menu_item_id)
      end
    end
  end
end
