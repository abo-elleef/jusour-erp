# frozen_string_literal: true

module MenuItemsHelper
  def menu_item_image_tag(menu_item, variant:, **options)
    attachment = menu_item.image_for(variant)
    return unless attachment

    image_tag(
      attachment,
      loading: options.delete(:loading) || "lazy",
      decoding: "async",
      **options
    )
  end
end
