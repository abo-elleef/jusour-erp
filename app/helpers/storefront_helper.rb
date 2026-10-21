# frozen_string_literal: true

module StorefrontHelper
  # The storefront's brand as CSS variables. Every value is re-checked here
  # (colors against a strict hex pattern, the font against the fixed list) so
  # nothing from the database reaches the stylesheet unvalidated.
  def storefront_theme_css(storefront)
    primary = storefront_safe_color(storefront.primary_color, "#b45309")
    accent = storefront_safe_color(storefront.accent_color, "#1c1917")
    rules = [
      "--sf-primary: #{primary}",
      "--sf-on-primary: #{Storefront.text_color_on(primary)}",
      "--sf-accent: #{accent}",
      "--sf-on-accent: #{Storefront.text_color_on(accent)}"
    ]
    css = ":root { #{rules.join('; ')}; }"
    family = Storefront::FONTS[storefront.font]
    css += %( body { font-family: "#{family}", ui-sans-serif, system-ui, sans-serif; }) if family
    tag.style(css.html_safe) # rubocop:disable Rails/OutputSafety -- built only from validated values above
  end

  def storefront_header_dark?
    @storefront&.header_style == "dark"
  end

  # A category's public name: its storefront row's title in the visitor's
  # language, or the inventory name. @storefront_categories is loaded once per
  # request by Public::StorefrontBaseController.
  def storefront_category_name(category)
    StorefrontCategory.display_name(category, @storefront_categories&.[](category.id))
  end

  def storefront_category_for(category)
    @storefront_categories&.[](category.id)
  end

  private

  def storefront_safe_color(value, fallback)
    value.to_s.downcase.match?(Storefront::HEX_COLOR) ? value.to_s.downcase : fallback
  end
end
