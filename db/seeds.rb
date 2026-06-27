# frozen_string_literal: true

require_relative "seeds/saqr_fried_chicken_menu"

puts "Seeding Saqr POS..."

company = Company.find_or_create_by!(slug: "default") do |c|
  c.name = "SAQR Fried Chicken"
  c.timezone = "Africa/Cairo"
  c.currency = "EGP"
  c.locale = "ar"
  c.active = true
end
company.update!(name: "SAQR Fried Chicken", timezone: "Africa/Cairo", currency: "EGP", locale: "ar")
Current.company = company

Setting.set("loyalty_earn_rate", "1")
Setting.set("loyalty_redeem_threshold", "100")
Setting.set("loyalty_redeem_value_cents", "500")
Setting.set("restaurant_name", "SAQR Fried Chicken")

User.find_or_create_by!(email: "owner@restaurant.com", company: company) do |u|
  u.name = "Owner"
  u.role = "owner"
  u.password = "changeme123"
  u.password_confirmation = "changeme123"
end

User.find_or_create_by!(email: "manager@restaurant.com", company: company) do |u|
  u.name = "Manager"
  u.role = "manager"
  u.password = "changeme123"
  u.password_confirmation = "changeme123"
  u.monthly_salary_cents = 450_000
end.tap { |u| u.update!(monthly_salary_cents: 450_000) if u.monthly_salary_cents.zero? }

User.find_or_create_by!(email: "cashier@restaurant.com", company: company) do |u|
  u.name = "Cashier"
  u.role = "cashier"
  u.password = "changeme123"
  u.password_confirmation = "changeme123"
  u.monthly_salary_cents = 300_000
end.tap { |u| u.update!(monthly_salary_cents: 300_000) if u.monthly_salary_cents.zero? }

User.find_or_create_by!(email: "kitchen@restaurant.com", company: company) do |u|
  u.name = "Kitchen"
  u.role = "kitchen"
  u.password = "changeme123"
  u.password_confirmation = "changeme123"
  u.monthly_salary_cents = 320_000
end.tap { |u| u.update!(monthly_salary_cents: 320_000) if u.monthly_salary_cents.zero? }

TaxRate.find_or_create_by!(name: "State Food Tax", tax_category: "food") do |t|
  t.rate = 0.08
  t.active = true
end

TaxRate.find_or_create_by!(name: "Beverage Tax", tax_category: "beverage") do |t|
  t.rate = 0.085
  t.active = true
end

puts "Seeding SAQR Fried Chicken menu (#{SaqrFriedChickenMenu::ITEMS.size} items)..."
SaqrFriedChickenMenu.seed!(company: company)
puts "  Active menu items: #{MenuItem.where(company: company, available: true).count}"

DiscountRule.find_or_create_by!(code: "WELCOME10") do |d|
  d.name = "Welcome 10% Off"
  d.discount_type = "percentage"
  d.discount_value = 10
  d.applies_to = "order"
  d.minimum_order_cents = 1000
  d.active = true
end

GiftCard.find_or_create_by!(code: "GIFT100") do |g|
  g.balance_cents = 10_000
  g.active = true
end

# Inventory
["Proteins", "Produce", "Dairy", "Dry Goods", "Sauces & Condiments", "Packaging"].each_with_index do |name, i|
  IngredientCategory.find_or_create_by!(name: name) { |c| c.position = i }
end

[
  { name: "Chicken Thighs", unit: "kg", category: "Proteins", reorder_threshold: 5, cost_per_unit_cents: 450, qty: 12 },
  { name: "Beef Patties (4oz)", unit: "pieces", category: "Proteins", reorder_threshold: 50, cost_per_unit_cents: 175, qty: 120 },
  { name: "Burger Buns", unit: "pieces", category: "Dry Goods", reorder_threshold: 100, cost_per_unit_cents: 30, qty: 200 },
  { name: "Chicken Buns", unit: "pieces", category: "Dry Goods", reorder_threshold: 100, cost_per_unit_cents: 28, qty: 150 },
  { name: "Shredded Lettuce", unit: "kg", category: "Produce", reorder_threshold: 2, cost_per_unit_cents: 180, qty: 4 },
  { name: "Tomatoes", unit: "kg", category: "Produce", reorder_threshold: 2, cost_per_unit_cents: 220, qty: 5 },
  { name: "American Cheese", unit: "pieces", category: "Dairy", reorder_threshold: 100, cost_per_unit_cents: 20, qty: 250 },
  { name: "Buttermilk", unit: "liters", category: "Dairy", reorder_threshold: 3, cost_per_unit_cents: 150, qty: 8 },
  { name: "Flour", unit: "kg", category: "Dry Goods", reorder_threshold: 10, cost_per_unit_cents: 80, qty: 25 },
  { name: "House Sauce", unit: "liters", category: "Sauces & Condiments", reorder_threshold: 2, cost_per_unit_cents: 300, qty: 6 },
  { name: "Fry Oil", unit: "liters", category: "Dry Goods", reorder_threshold: 10, cost_per_unit_cents: 200, qty: 20 },
  { name: "Takeout Boxes", unit: "pieces", category: "Packaging", reorder_threshold: 200, cost_per_unit_cents: 15, qty: 500 }
].each do |attrs|
  cat = IngredientCategory.find_by!(name: attrs[:category])
  ing = Ingredient.find_or_create_by!(name: attrs[:name]) do |i|
    i.ingredient_category = cat
    i.unit = attrs[:unit]
    i.reorder_threshold = attrs[:reorder_threshold]
    i.cost_per_unit_cents = attrs[:cost_per_unit_cents]
    i.quantity_on_hand = attrs[:qty]
  end
  StockBatch.find_or_create_by!(ingredient: ing, batch_reference: "SEED-#{ing.name.parameterize}") do |b|
    b.quantity_received = ing.quantity_on_hand
    b.quantity_remaining = ing.quantity_on_hand
    b.cost_per_unit_cents = ing.cost_per_unit_cents
    b.received_on = Date.current
    b.expires_on = 30.days.from_now.to_date
  end
end

supplier = Supplier.find_or_create_by!(name: "Metro Food Distributors") do |s|
  s.contact_name = "John Metro"
  s.email = "orders@metrofood.example.com"
  s.phone = "555-0100"
  s.lead_time_days = 2
end

Ingredient.active.find_each do |ing|
  SupplierIngredient.find_or_create_by!(supplier: supplier, ingredient: ing) do |si|
    si.price_cents = ing.cost_per_unit_cents
    si.preferred = true
  end
end

chicken = Ingredient.find_by(name: "Chicken Thighs")
buttermilk = Ingredient.find_by(name: "Buttermilk")
proteins_cat = IngredientCategory.find_by(name: "Proteins")
if chicken && buttermilk && proteins_cat
  marinated = Ingredient.find_or_create_by!(name: "Marinated Chicken (Prep)") do |i|
    i.ingredient_category = proteins_cat
    i.unit = "kg"
    i.reorder_threshold = 3
    i.cost_per_unit_cents = 0
    i.quantity_on_hand = 0
  end

  template = ManufacturingTemplate.find_or_create_by!(name: "Marinate Chicken Batch") do |t|
    t.output_ingredient = marinated
    t.yield_quantity = 5
    t.position = 1
    t.active = false
  end
  ManufacturingTemplateLine.find_or_create_by!(manufacturing_template: template, ingredient: chicken) do |l|
    l.quantity_used = 4
  end
  ManufacturingTemplateLine.find_or_create_by!(manufacturing_template: template, ingredient: buttermilk) do |l|
    l.quantity_used = 2
  end
  template.update!(active: true) if template.manufacturing_template_lines.any?
end

[
  { name: "COGS", category_type: "cogs", system_managed: true, position: 1 },
  { name: "Vendor purchases", category_type: "other", system_managed: true, position: 0 },
  { name: "Labor", category_type: "labor", system_managed: true, position: 2 },
  { name: "Rent", category_type: "rent", system_managed: false, position: 3 },
  { name: "Utilities", category_type: "utilities", system_managed: false, position: 4 },
  { name: "Marketing", category_type: "marketing", system_managed: false, position: 5 },
  { name: "Maintenance", category_type: "maintenance", system_managed: false, position: 6 },
  { name: "Other", category_type: "other", system_managed: false, position: 7 }
].each do |attrs|
  ExpenseCategory.find_or_create_by!(name: attrs[:name]) { |e| e.assign_attributes(attrs) }
end

[
  { name: "POS Sales", category_type: "sales", system_managed: true, position: 1 },
  { name: "Catering", category_type: "catering", system_managed: false, position: 2 },
  { name: "Delivery Fees", category_type: "delivery", system_managed: false, position: 3 },
  { name: "Services", category_type: "services", system_managed: false, position: 4 },
  { name: "Other Income", category_type: "other", system_managed: false, position: 5 }
].each do |attrs|
  IncomeCategory.find_or_create_by!(name: attrs[:name]) { |e| e.assign_attributes(attrs) }
end

[
  { name: "Main Safe", treasury_type: "safe", opening_balance_cents: 500_000, balance_cents: 500_000, is_default: true, position: 1 },
  { name: "Front Register", treasury_type: "cash_drawer", opening_balance_cents: 50_000, balance_cents: 50_000, position: 2 },
  { name: "Bank Account", treasury_type: "bank", opening_balance_cents: 1_000_000, balance_cents: 1_000_000, position: 3 }
].each do |attrs|
  Treasury.find_or_create_by!(name: attrs[:name]) do |t|
    t.assign_attributes(attrs)
  end.tap do |t|
    t.update!(attrs.except(:name)) unless t.balance_cents == attrs[:balance_cents]
  end
end

OvertimeRule.find_or_create_by!(name: "Federal Standard") do |r|
  r.weekly_threshold_hours = 40.0
  r.ot_multiplier = 1.5
  r.active = true
end

current_month = Date.current
ExpenseCategory.where(system_managed: false).find_each do |cat|
  Budget.find_or_create_by!(expense_category: cat, year: current_month.year, month: current_month.month) do |b|
    b.amount_cents = 200_000
  end
end


main_branch = Location.find_or_create_by!(company: company, name: "Main Branch") do |l|
  l.location_type = "branch"
  l.active = true
  l.position = 0
end

Printer.find_or_create_by!(name: "Front Counter Receipt") do |p|
  p.printer_type = "receipt"
  p.connection_type = "network"
  p.host = "192.168.1.100"
  p.port = 9100
  p.station = "Front counter"
  p.location = main_branch
  p.is_default = true
end

Printer.find_or_create_by!(name: "Kitchen Hot Line") do |p|
  p.printer_type = "kitchen"
  p.connection_type = "network"
  p.host = "192.168.1.101"
  p.port = 9100
  p.station = "Hot line"
  p.location = main_branch
  p.is_default = true
end

Printer.where(location_id: nil).find_each do |printer|
  printer.update!(location: main_branch)
end

SaqrFriedChickenMenu.seed_location_menu!(location: main_branch)

SuperAdminUser.find_or_create_by!(email: "superadmin@saqr.io") do |sa|
  sa.name = "Super Admin"
  sa.password = "superadmin123"
  sa.password_confirmation = "superadmin123"
end

puts "Seed complete. Login: owner@restaurant.com / changeme123"
puts "Super admin login: superadmin@saqr.io / superadmin123  →  /super_admin"

Setting.set("print_routing", Printing::Config::ROUTING_CLIENT) if Setting.get("print_routing").blank?
Setting.set("print_agent_port", Printing::Config::DEFAULT_AGENT_PORT) if Setting.get("print_agent_port").blank?
