# frozen_string_literal: true

class AddSlugToLocations < ActiveRecord::Migration[7.1]
  def up
    add_column :locations, :slug, :string
    add_index :locations, %i[company_id slug], unique: true

    Location.reset_column_information
    Location.unscoped.find_each do |location|
      base = location.name.to_s.parameterize.presence || "location"
      slug = base
      counter = 1
      while Location.unscoped.where(company_id: location.company_id, slug: slug).where.not(id: location.id).exists?
        slug = "#{base}-#{counter}"
        counter += 1
      end
      location.update_column(:slug, slug)
    end

    change_column_null :locations, :slug, false
  end

  def down
    remove_index :locations, column: %i[company_id slug]
    remove_column :locations, :slug
  end
end
