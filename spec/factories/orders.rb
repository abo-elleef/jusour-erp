# frozen_string_literal: true

FactoryBot.define do
  factory :category do
    sequence(:name) { |n| "Category #{n}" }
    position { 1 }
    active { true }
  end

  factory :menu_item do
    category
    name { "Test Item" }
    base_price_cents { 999 }
    tax_category { "food" }
    available { true }
  end

  factory :customer do
    name { "Test Customer" }
    email { Faker::Internet.unique.email }
    phone { nil }
  end

  factory :order do
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
