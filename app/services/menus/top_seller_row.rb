# frozen_string_literal: true

module Menus
  # The cards of the "Most sold" row for one screen: the register (:pos) or the
  # online menu (:public, which the call center orders from too).
  #
  # Pinned items come first, in the order the manager set (Locations → edit);
  # the rest of the row is filled from this branch's best sellers of the last 14
  # days (Menus::TopSellers), skipping the pinned ones. Both are mapped onto the
  # items already loaded for that screen, so an item not sold there (unavailable
  # at the branch, or in a category shown on the other screen only) drops out and
  # its price and promo match the menu below it.
  #
  # Empty when the branch has the row turned off for that screen.
  class TopSellerRow
    # Read more sales than the row holds, so items that drop out on this screen
    # still leave a full row.
    SALES_LOOKUP = Location::TOP_SELLERS_ROW_SIZE * 3

    def self.call(location:, channel:, menu_items:)
      new(location:, channel:, menu_items:).call
    end

    def initialize(location:, channel:, menu_items:)
      @location = location
      @channel = channel
      @menu_items = menu_items
    end

    def call
      return [] unless @location&.top_sellers_on?(@channel)

      items_by_id = @menu_items.index_by(&:id)
      ids = @location.top_seller_pinned_item_ids + Menus::TopSellers.call(location: @location, limit: SALES_LOOKUP)
      ids.uniq.filter_map { |id| items_by_id[id] }.first(Location::TOP_SELLERS_ROW_SIZE)
    end
  end
end
