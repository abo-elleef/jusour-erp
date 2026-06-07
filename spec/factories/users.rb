# frozen_string_literal: true

FactoryBot.define do
  factory :user do
    company { Current.company }
    name { Faker::Name.name }
    email { Faker::Internet.unique.email }
    password { "password123" }
    password_confirmation { "password123" }
    role { "cashier" }

    trait :owner do
      role { "owner" }
    end

    trait :manager do
      role { "manager" }
    end
  end
end
