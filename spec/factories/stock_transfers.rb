# frozen_string_literal: true

FactoryBot.define do
  factory :stock_transfer do
    company { Current.company }
    from_location { association :location, :central_kitchen, company: company }
    to_location { association :location, company: company }
    requested_by { association :user, :manager, company: company }
    requested_at { Time.current }
    status { "requested" }

    trait :sent do
      status { "sent" }
      sent_at { Time.current }
      sent_by { requested_by }
    end

    trait :received do
      sent
      status { "received" }
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
  end
end
