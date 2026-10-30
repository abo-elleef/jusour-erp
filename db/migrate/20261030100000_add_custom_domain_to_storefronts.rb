# frozen_string_literal: true

class AddCustomDomainToStorefronts < ActiveRecord::Migration[7.1]
  def change
    add_column :storefronts, :custom_domain, :string
    add_index :storefronts, "lower(custom_domain)", unique: true, where: "custom_domain IS NOT NULL",
      name: "index_storefronts_on_lower_custom_domain"
  end
end
