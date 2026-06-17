# frozen_string_literal: true

module Menus
  class ForLocation
    Result = Struct.new(:categories, :menu_items, :combos, keyword_init: true)

    def self.call(location:)
      new(location:).call
    end

    def initialize(location:)
      @location = location
    end

    def call
      return empty_result if @location.blank?

      menu_items = MenuItem.available_at_location(@location)
        .includes(:category, :location_menu_items, image_attachment: :blob, modifier_groups: :modifiers)
        .order(:position, :name)
      combos = Combo.available_at_location(@location).order(:name)
      category_ids = menu_items.map(&:category_id).uniq
      categories = Category.active.ordered.select { |category| category_ids.include?(category.id) }

      Result.new(categories:, menu_items:, combos:)
    end

    private

    def empty_result
      Result.new(categories: Category.none, menu_items: MenuItem.none, combos: Combo.none)
    end
  end
end
