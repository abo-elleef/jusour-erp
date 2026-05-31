# frozen_string_literal: true

require "rails_helper"

RSpec.describe Customer, type: :model do
  describe "validations" do
    it "requires email or phone" do
      customer = build(:customer, email: nil, phone: nil)
      expect(customer).not_to be_valid
      expect(customer.errors[:base]).to include(I18n.t("customers.errors.email_or_phone_required"))
    end

    it "is valid with phone only" do
      expect(build(:customer, email: nil, phone: "555-9999")).to be_valid
    end

    it "enforces unique email" do
      create(:customer, email: "dup@test.com", phone: "555-0001")
      duplicate = build(:customer, email: "dup@test.com", phone: "555-0002")
      expect(duplicate).not_to be_valid
    end
  end
end
