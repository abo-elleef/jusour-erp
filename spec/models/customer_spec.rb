# frozen_string_literal: true

require "rails_helper"

RSpec.describe Customer, type: :model do
  let(:company) { create(:company) }

  before { Current.company = company }

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
      expect(duplicate.errors[:email]).to be_present
    end

    it "enforces unique phone" do
      create(:customer, email: nil, phone: "555-1111")
      duplicate = build(:customer, email: nil, phone: "555-1111")
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:phone]).to be_present
    end

    it "rejects a phone that matches another customer's secondary phone" do
      create(:customer, email: nil, phone: "555-1000", phone_secondary: "555-2000")
      duplicate = build(:customer, email: nil, phone: "555-2000")
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:phone]).to include(I18n.t("customers.errors.phone_taken"))
    end

    it "strips contact fields before validating" do
      create(:customer, email: nil, phone: "555-3333")
      duplicate = build(:customer, email: nil, phone: " 555-3333 ")
      expect(duplicate).not_to be_valid
      expect(duplicate.phone).to eq("555-3333")
    end
  end

  describe "unique constraint rescue" do
    it "turns RecordNotUnique into a validation error instead of raising" do
      create(:customer, email: nil, phone: "555-4444")
      duplicate = build(:customer, email: nil, phone: "555-4444")
      allow(duplicate).to receive(:valid?).and_return(true)

      expect(duplicate.save).to eq(false)
      expect(duplicate.errors[:phone]).to include(I18n.t("customers.errors.phone_taken"))
    end
  end
end
