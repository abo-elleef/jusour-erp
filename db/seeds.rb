# frozen_string_literal: true

puts "Seeding Saqr POS..."

Setting.set("loyalty_earn_rate", "1")
Setting.set("loyalty_redeem_threshold", "100")
Setting.set("loyalty_redeem_value_cents", "500")

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
end

User.find_or_create_by!(email: "cashier@restaurant.com") do |u|
  u.name = "Cashier"
  u.role = "cashier"
  u.password = "changeme123"
  u.password_confirmation = "changeme123"
end

User.find_or_create_by!(email: "kitchen@restaurant.com") do |u|
  u.name = "Kitchen"
  u.role = "kitchen"
  u.password = "changeme123"
  u.password_confirmation = "changeme123"
end

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

items.each_with_index do |data, i|
  item = MenuItem.find_or_create_by!(name: data[:name], category: data[:cat]) do |m|
    m.base_price_cents = data[:price]
    m.tax_category = data[:tax]
    m.available = true
    m.position = i
    m.description = "House favorite"
  end
  data[:mods].each do |mg_data|
    group = item.modifier_groups.find_or_create_by!(name: mg_data[:group]) do |g|
      g.required = mg_data[:required] || false
      g.multi_select = false
    end
    mg_data[:mods].each_with_index do |(name, cents), j|
      group.modifiers.find_or_create_by!(name: name) do |mod|
        mod.price_adjustment_cents = cents
        mod.position = j
      end
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

puts "Seed complete. Login: owner@restaurant.com / changeme123"
