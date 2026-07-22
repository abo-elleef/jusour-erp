# frozen_string_literal: true

# Give ingredient categories a name-derived code, and code each ingredient as
# "<CATEGORY_CODE>-NNN" (like menu items, but the category code tracks its name).
class AddCodeToIngredientCategoriesAndIngredients < ActiveRecord::Migration[7.1]
  def up
    add_column :ingredient_categories, :code, :string
    add_column :ingredients, :code, :string

    # Backfill category codes from the name (Unicode letters/digits kept, so
    # Arabic names stay meaningful), deduped per company.
    seen = Hash.new { |h, k| h[k] = {} }
    select_rows("SELECT id, company_id, name FROM ingredient_categories ORDER BY company_id, position, name").each do |id, company_id, name|
      base = name.to_s.strip.upcase.gsub(/[^\p{Alnum}]+/, "")
      base = "CAT" if base.blank?
      code = base
      n = 1
      while seen[company_id][code.upcase]
        n += 1
        code = "#{base}#{n}"
      end
      seen[company_id][code.upcase] = true
      execute("UPDATE ingredient_categories SET code = #{quote(code)} WHERE id = #{quote(id)}")
    end

    # Code each ingredient as <category.code>-NNN, per category, in creation order.
    execute <<~SQL.squish
      UPDATE ingredients SET code = sub.new_code FROM (
        SELECT i.id,
               c.code || '-' || LPAD(
                 (ROW_NUMBER() OVER (PARTITION BY i.ingredient_category_id ORDER BY i.created_at, i.id))::text, 3, '0'
               ) AS new_code
        FROM ingredients i
        JOIN ingredient_categories c ON c.id = i.ingredient_category_id
      ) sub
      WHERE ingredients.id = sub.id
    SQL

    change_column_null :ingredient_categories, :code, false
    change_column_null :ingredients, :code, false
    add_index :ingredient_categories, "company_id, lower(code)", unique: true, name: "index_ingredient_categories_on_company_and_lower_code"
    add_index :ingredients, "company_id, lower(code)", unique: true, name: "index_ingredients_on_company_and_lower_code"
  end

  def down
    remove_index :ingredient_categories, name: "index_ingredient_categories_on_company_and_lower_code"
    remove_index :ingredients, name: "index_ingredients_on_company_and_lower_code"
    remove_column :ingredients, :code
    remove_column :ingredient_categories, :code
  end
end
