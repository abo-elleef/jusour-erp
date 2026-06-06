# frozen_string_literal: true

puts "Seeding Saqr POS..."

Setting.set("loyalty_earn_rate", "1")
Setting.set("loyalty_redeem_threshold", "100")
Setting.set("loyalty_redeem_value_cents", "500")
Setting.set("restaurant_name", "Saqr Chicken & Burgers")

User.find_or_create_by!(email: "owner@restaurant.com") do |u|
  u.name = "Owner"
  u.role = "owner"
  u.password = "changeme123"
  u.password_confirmation = "changeme123"
end

User.find_or_create_by!(email: "manager@restaurant.com") do |u|
  u.name = "Manager"
  u.role = "manager"
  u.password = "changeme123"
  u.password_confirmation = "changeme123"
  u.monthly_salary_cents = 450_000
end.tap { |u| u.update!(monthly_salary_cents: 450_000) if u.monthly_salary_cents.zero? }

User.find_or_create_by!(email: "cashier@restaurant.com") do |u|
  u.name = "Cashier"
  u.role = "cashier"
  u.password = "changeme123"
  u.password_confirmation = "changeme123"
  u.monthly_salary_cents = 300_000
end.tap { |u| u.update!(monthly_salary_cents: 300_000) if u.monthly_salary_cents.zero? }

User.find_or_create_by!(email: "kitchen@restaurant.com") do |u|
  u.name = "Kitchen"
  u.role = "kitchen"
  u.password = "changeme123"
  u.password_confirmation = "changeme123"
  u.monthly_salary_cents = 320_000
end.tap { |u| u.update!(monthly_salary_cents: 320_000) if u.monthly_salary_cents.zero? }

%w[Chicken Burgers Sides Drinks Combos].each_with_index do |name, i|
  Category.find_or_create_by!(name: name) { |c| c.position = i; c.active = true }
end

TaxRate.find_or_create_by!(name: "State Food Tax", tax_category: "food") do |t|
  t.rate = 0.08
  t.active = true
end

TaxRate.find_or_create_by!(name: "Beverage Tax", tax_category: "beverage") do |t|
  t.rate = 0.085
  t.active = true
end

chicken = Category.find_by!(name: "Chicken")
burgers = Category.find_by!(name: "Burgers")
sides = Category.find_by!(name: "Sides")
drinks = Category.find_by!(name: "Drinks")

items = [
  { cat: chicken, name: "Classic Fried Chicken (2pc)", price: 899, tax: "food",
    mods: [{ group: "Spice Level", mods: [["Mild", 0], ["Hot", 0], ["Extra Hot", 50]] }] },
  { cat: chicken, name: "Nashville Hot Tenders (3pc)", price: 1099, tax: "food",
    mods: [{ group: "Sauce Choice", mods: [["Ranch", 0], ["Honey Mustard", 0], ["No Sauce", 0]] }] },
  { cat: burgers, name: "Smash Burger", price: 1199, tax: "food",
    mods: [{ group: "Cheese", required: true, mods: [["American", 0], ["Pepper Jack", 100], ["No Cheese", 0]] }] },
  { cat: burgers, name: "Double Smash", price: 1499, tax: "food", mods: [] },
  { cat: sides, name: "Crinkle Fries", price: 399, tax: "food", mods: [] },
  { cat: sides, name: "Mac & Cheese", price: 499, tax: "food", mods: [] },
  { cat: drinks, name: "Sweet Tea", price: 299, tax: "beverage", mods: [] },
  { cat: drinks, name: "Fountain Soda", price: 249, tax: "beverage", mods: [] },
  # Additional menu items
  { cat: chicken, name: "Fried Chicken (4pc)", price: 1299, tax: "food",
    mods: [{ group: "Spice Level", mods: [["Mild", 0], ["Hot", 0], ["Extra Hot", 50]] }] },
  { cat: chicken, name: "Nashville Hot Sandwich", price: 1099, tax: "food", mods: [] },
  { cat: chicken, name: "Crispy Chicken Sandwich", price: 999, tax: "food",
    mods: [{ group: "Sauce", mods: [["Mayo", 0], ["Spicy Mayo", 0], ["No Sauce", 0]] }] },
  { cat: chicken, name: "Buffalo Wings (6pc)", price: 899, tax: "food",
    mods: [{ group: "Wing Sauce", mods: [["Buffalo", 0], ["BBQ", 0], ["Garlic Parmesan", 100]] }] },
  { cat: chicken, name: "Chicken Biscuit", price: 699, tax: "food", mods: [] },
  { cat: burgers, name: "Bacon Smash Burger", price: 1399, tax: "food",
    mods: [{ group: "Cheese", required: true, mods: [["American", 0], ["Pepper Jack", 100], ["No Cheese", 0]] }] },
  { cat: burgers, name: "Mushroom Swiss Smash", price: 1499, tax: "food", mods: [] },
  { cat: burgers, name: "Chicken Club Burger", price: 1199, tax: "food", mods: [] },
  { cat: burgers, name: "Grilled Chicken Wrap", price: 1099, tax: "food", mods: [] },
  { cat: sides, name: "Onion Rings", price: 449, tax: "food", mods: [] },
  { cat: sides, name: "Coleslaw", price: 299, tax: "food", mods: [] },
  { cat: sides, name: "Buttermilk Biscuit", price: 199, tax: "food", mods: [] },
  { cat: sides, name: "Mashed Potatoes", price: 449, tax: "food", mods: [] },
  { cat: sides, name: "Cornbread", price: 349, tax: "food", mods: [] },
  { cat: drinks, name: "Fresh Lemonade", price: 299, tax: "beverage", mods: [] },
  { cat: drinks, name: "Bottled Water", price: 199, tax: "beverage", mods: [] }
]

modifier_group_cache = {}

items.each_with_index do |data, i|
  item = MenuItem.find_or_create_by!(name: data[:name], category: data[:cat]) do |m|
    m.base_price_cents = data[:price]
    m.tax_category = data[:tax]
    m.available = true
    m.position = i
    m.description = "House favorite"
  end
  data[:mods].each_with_index do |mg_data, idx|
    group_name = mg_data[:group]
    group = modifier_group_cache[group_name] ||= begin
      g = ModifierGroup.find_or_create_by!(name: group_name) do |gr|
        gr.required = mg_data[:required] || false
        gr.multi_select = false
      end
      g.update!(required: true) if mg_data[:required] && !g.required?
      mg_data[:mods].each_with_index do |(name, cents), j|
        g.modifiers.find_or_create_by!(name: name) do |mod|
          mod.price_adjustment_cents = cents
          mod.position = j
        end
      end
      g
    end
    MenuItemModifierGroup.find_or_create_by!(menu_item: item, modifier_group: group) do |join|
      join.position = idx
    end
  end
end

combo_cat = Category.find_by!(name: "Combos")
combo1 = Combo.find_or_create_by!(name: "Chicken Combo") do |c|
  c.description = "2pc chicken + fries + drink"
  c.price_cents = 1399
  c.active = true
end
combo1.combo_items.find_or_create_by!(menu_item: MenuItem.find_by!(name: "Classic Fried Chicken (2pc)"))
combo1.combo_items.find_or_create_by!(menu_item: MenuItem.find_by!(name: "Crinkle Fries"))
combo1.combo_items.find_or_create_by!(menu_item: MenuItem.find_by!(name: "Sweet Tea"))

combo2 = Combo.find_or_create_by!(name: "Smash Meal") do |c|
  c.description = "Smash burger + fries + soda"
  c.price_cents = 1599
  c.active = true
end
combo2.combo_items.find_or_create_by!(menu_item: MenuItem.find_by!(name: "Smash Burger"))
combo2.combo_items.find_or_create_by!(menu_item: MenuItem.find_by!(name: "Crinkle Fries"))
combo2.combo_items.find_or_create_by!(menu_item: MenuItem.find_by!(name: "Fountain Soda"))

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

smash = MenuItem.find_by(name: "Smash Burger")
patty = Ingredient.find_by(name: "Beef Patties (4oz)")
bun = Ingredient.find_by(name: "Burger Buns")
if smash && patty && bun
  Recipe.find_or_create_by!(menu_item: smash, ingredient: patty) { |r| r.quantity_used = 1 }
  Recipe.find_or_create_by!(menu_item: smash, ingredient: bun) { |r| r.quantity_used = 1 }
end

[
  { name: "COGS", category_type: "cogs", system_managed: true, position: 1 },
  { name: "Labor", category_type: "labor", system_managed: true, position: 2 },
  { name: "Rent", category_type: "rent", system_managed: false, position: 3 },
  { name: "Utilities", category_type: "utilities", system_managed: false, position: 4 },
  { name: "Marketing", category_type: "marketing", system_managed: false, position: 5 },
  { name: "Maintenance", category_type: "maintenance", system_managed: false, position: 6 },
  { name: "Other", category_type: "other", system_managed: false, position: 7 }
].each do |attrs|
  ExpenseCategory.find_or_create_by!(name: attrs[:name]) { |e| e.assign_attributes(attrs) }
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


Printer.find_or_create_by!(name: "Front Counter Receipt") do |p|
  p.printer_type = "receipt"
  p.connection_type = "network"
  p.host = "192.168.1.100"
  p.port = 9100
  p.location = "Front counter"
  p.is_default = true
end

Printer.find_or_create_by!(name: "Kitchen Hot Line") do |p|
  p.printer_type = "kitchen"
  p.connection_type = "network"
  p.host = "192.168.1.101"
  p.port = 9100
  p.location = "Hot line"
  p.is_default = true
end

puts "Seed complete. Login: owner@restaurant.com / changeme123"
