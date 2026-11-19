# frozen_string_literal: true

require "rails_helper"

RSpec.describe Customer, "phone rules", type: :model do
  let(:company) { create(:company) }

  before { Current.company = company }

  it "stores phones normalised from Arabic digits, spaces and dashes" do
    customer = create(:customer, phone: "٠١٠-١٢٣٤ ٥٦٧٨", phone_secondary: "۰۱۱ ۱۲۳۴ ۵۶۷۸")
    expect(customer.reload.phone).to eq("01012345678")
    expect(customer.phone_secondary).to eq("01112345678")
  end

  describe "exactly 11 digits" do
    it "is off by default" do
      expect(build(:customer, phone: "555-9999")).to be_valid
    end

    it "checks both phones when the company turns it on" do
      Setting.set("require_eleven_digit_phones", true)

      expect(build(:customer, phone: "0101234567")).not_to be_valid
      customer = build(:customer, phone: "01012345678", phone_secondary: "0111234567")
      expect(customer).not_to be_valid
      expect(customer.errors[:phone_secondary]).to include(I18n.t("phones.errors.eleven_digits", field: described_class.human_attribute_name(:phone_secondary)))
      expect(build(:customer, phone: "٠١٠١٢٣٤٥٦٧٨")).to be_valid
    end

    it "leaves an old customer saving while the phone is unchanged" do
      old = create(:customer, phone: "5559999")
      old.update_columns(phone: "555 9999") # stored before normalising existed
      Setting.set("require_eleven_digit_phones", true)

      expect(old.reload.update(name: "Renamed")).to be(true)
      expect(old.reload.phone).to eq("555 9999")
    end

    it "skips the length rule for system paths that ask it to" do
      Setting.set("require_eleven_digit_phones", true)
      expect(build(:customer, phone: "0101234", skip_phone_length_check: true)).to be_valid
    end
  end
end
