# frozen_string_literal: true

# The five starting ticket categories, for every company that exists today.
# New companies get the same list from TicketCategory.seed_defaults! (keep the
# two lists in step). Raw SQL on purpose — no app models in migrations.
class SeedTicketCategories < ActiveRecord::Migration[7.1]
  DEFAULTS = [
    ["product_quality", "Product quality", "جودة المنتج"],
    ["wrong_or_missing_item", "Wrong or missing item", "صنف خاطئ أو ناقص"],
    ["delivery_problem", "Delivery problem", "مشكلة في التوصيل"],
    ["price_or_billing", "Price or billing", "السعر أو الفاتورة"],
    ["other", "Other", "أخرى"]
  ].freeze

  def up
    values = DEFAULTS.each_with_index.map do |(key, name, name_ar), position|
      "(#{quote(key)}, #{quote(name)}, #{quote(name_ar)}, #{position})"
    end.join(", ")

    execute <<~SQL.squish
      INSERT INTO ticket_categories (id, company_id, key, name, name_ar, position, active, created_at, updated_at)
      SELECT gen_random_uuid(), companies.id, d.key, d.name, d.name_ar, d.position, TRUE, NOW(), NOW()
      FROM companies
      CROSS JOIN (VALUES #{values}) AS d(key, name, name_ar, position)
      ON CONFLICT DO NOTHING
    SQL
  end

  def down
    execute "DELETE FROM ticket_categories WHERE key IS NOT NULL"
  end

  private

  def quote(value)
    connection.quote(value)
  end
end
