# frozen_string_literal: true

# The Google Maps link is a contact detail like the phone or address, so it
# moves from the (removed) home-page Contact block into Website settings.
# Contact blocks are deleted — the footer and the Contact page show the same
# details on every page.
class AddMapUrlToStorefronts < ActiveRecord::Migration[7.1]
  def up
    add_column :storefronts, :map_url, :string, null: false, default: ""

    execute(<<~SQL.squish)
      UPDATE storefronts SET map_url = sections.settings->>'map_url'
      FROM storefront_sections sections
      WHERE sections.storefront_id = storefronts.id
        AND sections.section_type = 'contact'
        AND COALESCE(sections.settings->>'map_url', '') <> ''
        AND storefronts.map_url = ''
    SQL
    execute("DELETE FROM storefront_sections WHERE section_type = 'contact'")
  end

  def down
    remove_column :storefronts, :map_url
  end
end
