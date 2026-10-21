# frozen_string_literal: true

# Storefront look & feel: brand colors, font, header style, an announcement
# bar, social links, and Arabic versions of the public copy. The existing text
# columns hold the English version; each *_ar column holds the Arabic one, and
# either falls back to the other when blank (see Storefront#localized).
class AddLookAndFeelToStorefronts < ActiveRecord::Migration[7.1]
  def change
    change_table :storefronts, bulk: true do |t|
      t.string :primary_color, null: false, default: "#b45309"
      t.string :accent_color, null: false, default: "#1c1917"
      t.string :font, null: false, default: "system"
      t.string :header_style, null: false, default: "light"

      t.boolean :announcement_enabled, null: false, default: false
      t.string :announcement_text, null: false, default: ""
      t.string :announcement_text_ar, null: false, default: ""
      t.string :announcement_url, null: false, default: ""

      t.string :facebook_url, null: false, default: ""
      t.string :instagram_url, null: false, default: ""
      t.string :tiktok_url, null: false, default: ""
      t.string :youtube_url, null: false, default: ""

      t.string :tagline_ar, null: false, default: ""
      t.text :about_ar, null: false, default: ""
      t.string :seo_description_ar, null: false, default: ""
    end
  end
end
