# frozen_string_literal: true

FactoryBot.define do
  factory :attendance_status do
    company { Current.company }
    sequence(:code) { |n| "status_#{n}" }
    sequence(:symbol) { |n| "S#{n}" }
    label { "Status" }
    paid_fraction { 1 }
    penalty_days { 0 }
    active { true }
  end
end
