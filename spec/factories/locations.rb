# frozen_string_literal: true

FactoryBot.define do
  factory :location do
    company { Current.company }
    sequence(:name) { |n| "Location #{n}" }
    location_type { "branch" }
    active { true }
    position { 0 }

    trait :central_kitchen do
      location_type { "central_kitchen" }
      name { "Central Kitchen" }
    end

    trait :branch do
      location_type { "branch" }
    end
  end

  factory :ingredient_category do
    company { Current.company }
    sequence(:name) { |n| "Ingredient Category #{n}" }
    active { true }
    position { 0 }
  end

  factory :ingredient do
    company { Current.company }
    ingredient_category
    sequence(:name) { |n| "Ingredient #{n}" }
    unit { "kg" }
    quantity_on_hand { 10.0 }
    reorder_threshold { 2.0 }
    cost_per_unit_cents { 500 }
    active { true }
  end

  factory :ingredient_location do
    ingredient
    location
    quantity_on_hand { 5.0 }
    reorder_threshold { 1.0 }
  end

  factory :location_menu_item do
    location
    menu_item
    available { true }
  end
end
