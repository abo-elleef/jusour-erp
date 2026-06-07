# frozen_string_literal: true

FactoryBot.define do
  factory :company do
    sequence(:name) { |n| "Test Company #{n}" }
    sequence(:slug) { |n| "test-company-#{n}" }
    timezone { "UTC" }
    currency { "USD" }
    locale { "en" }
    active { true }
  end
end
