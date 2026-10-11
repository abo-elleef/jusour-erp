# frozen_string_literal: true

FactoryBot.define do
  factory :lead do
    company { Current.company }
    association :created_by, factory: :user
    sequence(:name) { |n| "Lead #{n}" }
    sequence(:phone) { |n| "010#{format('%08d', n)}" }
    stage { "new" }
  end

  factory :lead_activity do
    lead
    user
    activity_type { "note" }
    note { "Called to introduce ourselves." }
    occurred_at { Time.current }
  end
end
