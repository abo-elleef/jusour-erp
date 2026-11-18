# frozen_string_literal: true

module Menus
  class ForLocation
    Result = Struct.new(:categories, :menu_items, :combos, :promos_by_item_id, keyword_init: true)

    # channel: :pos (the register, online and offline) or :public (the public
    # menu). Items whose category is set to show on the other channel only are
    # left out (Category#menu_visibility). Combos are not in a category, so they
    # show on both.
    def self.call(location:, channel:)
      new(location:, channel:).call
    end

    def initialize(location:, channel:)
      @location = location
      @channel = channel
    end

    def call
      return empty_result if @location.blank?

      menu_items = MenuItem.available_at_location(@location)
        .where(category_id: Category.shown_on(@channel).select(:id))
        .includes(:category, :location_menu_items, image_attachment: :blob, modifier_groups: :modifiers)
        .order(:position, :name)
      combos = Combo.available_at_location(@location).order(:name)
      category_ids = menu_items.map(&:category_id).uniq
      categories = Category.active.ordered.select { |category| category_ids.include?(category.id) }
      promos_by_item_id = ActivePromo.index_for(menu_items: menu_items, location: @location)

      Result.new(categories:, menu_items:, combos:, promos_by_item_id:)
    end

    private

    def empty_result
      Result.new(
        categories: Category.none,
        menu_items: MenuItem.none,
        combos: Combo.none,
        promos_by_item_id: {}
      )
    end
  end
end
