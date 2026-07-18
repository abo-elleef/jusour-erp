# frozen_string_literal: true

# Give menu categories their own short code, then recode menu items as
# "<CATEGORY_CODE>-NNN" so the category is embedded in each item's reference.
class AddCodeToCategoriesAndRecodeMenuItems < ActiveRecord::Migration[7.1]
  def up
    add_column :categories, :code, :string

    # Backfill category codes from the name (first alphanumerics), deduped per company.
    seen = Hash.new { |h, k| h[k] = {} }
    select_rows("SELECT id, company_id, name FROM categories ORDER BY company_id, position, name").each do |id, company_id, name|
      base = name.to_s.upcase.gsub(/[^A-Z0-9]/, "")[0, 4]
      base = "CAT" if base.blank?
      code = base
      n = 1
      while seen[company_id][code]
        n += 1
        code = "#{base}#{n}"
      end
      seen[company_id][code] = true
      execute("UPDATE categories SET code = #{quote(code)} WHERE id = #{quote(id)}")
    end

    change_column_null :categories, :code, false
    add_index :categories, "company_id, lower(code)", unique: true, name: "index_categories_on_company_and_lower_code"

    # Recode menu items as <category.code>-NNN, per category, in creation order.
    execute <<~SQL.squish
      UPDATE menu_items SET code = sub.new_code FROM (
        SELECT mi.id,
               c.code || '-' || LPAD(
                 (ROW_NUMBER() OVER (PARTITION BY mi.category_id ORDER BY mi.created_at, mi.id))::text, 3, '0'
               ) AS new_code
        FROM menu_items mi
        JOIN categories c ON c.id = mi.category_id
      ) sub
      WHERE menu_items.id = sub.id
    SQL
  end

  def down
    remove_index :categories, name: "index_categories_on_company_and_lower_code"
    remove_column :categories, :code
  end
end
