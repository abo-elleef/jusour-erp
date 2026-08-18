# frozen_string_literal: true

FactoryBot.define do
  factory :stock_transfer do
    company { Current.company }
    from_location { association :location, :central_kitchen, company: company }
    to_location { association :location, company: company }
    requested_by { association :user, :manager, company: company }
    requested_at { Time.current }
    transferred_on { Date.current }
    status { "requested" }

    trait :awaiting_receipt do
      status { "awaiting_receipt" }
      sent_at { Time.current }
      sent_by { requested_by }
    end

    trait :partially_received do
      status { "partially_received" }
      sent_at { Time.current }
      sent_by { requested_by }
      received_at { Time.current }
      received_by { requested_by }
    end

    trait :completed do
      status { "completed" }
      sent_at { Time.current }
      sent_by { requested_by }
      received_at { Time.current }
      received_by { requested_by }
    end

    after(:build) do |transfer|
      transfer.transfer_number ||= "ST-TEST-#{SecureRandom.hex(4)}"
    end
  end

  factory :stock_transfer_line do
    stock_transfer
    ingredient
    quantity_requested { 5.0 }
    quantity_sent { 0 }
    quantity_received { 0 }
  end

  factory :stock_transfer_shipment do
    stock_transfer
    sequence(:sequence) { |n| n }
    status { "in_transit" }
    sent_by { stock_transfer.requested_by }
    sent_at { Time.current }
  end
end
