# frozen_string_literal: true

FactoryBot.define do
  factory :category do
    company { Current.company }
    sequence(:name) { |n| "Category #{n}" }
    position { 1 }
    active { true }
  end

  factory :menu_item do
    company { Current.company }
    category { association :category, company: company }
    name { "Test Item" }
    base_price_cents { 999 }
    tax_category { "food" }
    available { true }
  end

  factory :customer do
    company { Current.company }
    name { "Test Customer" }
    email { Faker::Internet.unique.email }
    phone { nil }
  end

  factory :shipping_company do
    company { Current.company }
    name { "Test Shipping Co" }
    active { true }
  end

  # No default treasury — always pass one explicitly (no :treasury factory exists;
  # other specs build Treasury directly with Treasury.create!).
  factory :sales_payment_method, class: "Sales::PaymentMethod" do
    company { Current.company }
    name { "Test Online Method" }
    active { true }
  end

  factory :order do
    company { user.company }
    user
    status { "draft" }
    subtotal_cents { 0 }
    discount_cents { 0 }
    tax_cents { 0 }
    tip_cents { 0 }
    total_cents { 0 }
  end

  factory :order_item do
    order
    menu_item
    quantity { 1 }
    unit_price_cents { 999 }
  end

  factory :payment do
    order
    payment_method { "cash" }
    amount_cents { 1000 }
    status { "completed" }
  end
end
