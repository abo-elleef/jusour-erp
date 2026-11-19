# frozen_string_literal: true

require "rails_helper"

# Bazzar slice A: one phone, one lead; a customer's phone can't start a new lead;
# optional 11-digit rule; numbers are normalised; old rows don't lock anyone out.
RSpec.describe Lead, "phone rules", type: :model do
  let(:company) { create(:company) }
  let(:creator) { create(:user, company: company) }

  before { Current.company = company }

  def new_lead(**attrs)
    build(:lead, created_by: creator, **attrs)
  end

  def require_eleven_digits!(on = true)
    Setting.set("require_eleven_digit_phones", on)
  end

  describe "normalising" do
    it "turns Arabic-Indic and Persian digits into Latin and drops spaces and dashes" do
      lead = new_lead(phone: "٠١٠ ١٢٣٤-٥٦٧٨", phone_secondary: "۰۱۱ ۱۲۳ ۴۵۶۷۸")
      lead.save!

      expect(lead.reload.phone).to eq("01012345678")
      expect(lead.phone_secondary).to eq("01112345678")
    end
  end

  describe "no repeated phone among leads" do
    let!(:existing) { create(:lead, created_by: creator, name: "Dr. Mona", phone: "01011111111", phone_secondary: "01022222222") }

    it "refuses the same primary phone, naming the existing lead" do
      lead = new_lead(phone: "01011111111")

      expect(lead).not_to be_valid
      error = lead.errors.find { |e| e.attribute == :phone }
      expect(error.message).to include("Dr. Mona")
      expect(error.options[:conflict]).to eq(existing)
    end

    it "checks both phones against both columns" do
      expect(new_lead(phone: "01022222222")).not_to be_valid
      expect(new_lead(phone: "01099999999", phone_secondary: "01011111111")).not_to be_valid
      expect(new_lead(phone: "01099999999", phone_secondary: "01022222222")).not_to be_valid
    end

    it "matches a number typed in Arabic digits" do
      expect(new_lead(phone: "٠١٠١١١١١١١١")).not_to be_valid
    end

    it "matches an old row stored with spaces" do
      existing.update_columns(phone: "0101 111 1111")
      expect(new_lead(phone: "01011111111")).not_to be_valid
    end

    it "counts lost and converted leads too" do
      existing.update_columns(stage: "lost", lost_reason: "price")
      expect(new_lead(phone: "01011111111")).not_to be_valid
    end

    it "does not compare across companies" do
      other = create(:company)
      Current.company = other
      expect(build(:lead, company: other, created_by: create(:user, company: other), phone: "01011111111")).to be_valid
    end

    it "lets a lead keep its own number on edit" do
      existing.notes = "Called back"
      expect(existing).to be_valid
    end
  end

  describe "phone that belongs to a customer" do
    let!(:customer) { create(:customer, name: "Al Shifa Clinic", phone: "01033333333", phone_secondary: "01044444444") }

    it "refuses it, naming the customer and pointing at it" do
      lead = new_lead(phone: "01044444444")

      expect(lead).not_to be_valid
      error = lead.errors.find { |e| e.attribute == :phone }
      expect(error.message).to include("Al Shifa Clinic")
      expect(error.options[:conflict]).to eq(customer)
    end

    it "checks the second phone as well" do
      expect(new_lead(phone: "01099999999", phone_secondary: "01033333333")).not_to be_valid
    end

    it "lets a converted lead and its own customer share the number" do
      lead = create(:lead, created_by: creator, phone: "01055555555", phone_secondary: "01066666666")
      converted_customer = lead.convert!(by: creator)

      expect(converted_customer).to be_persisted
      expect(lead.reload).to be_converted
      expect(converted_customer.phone).to eq("01055555555")

      lead.phone_secondary = "01077777777"
      lead.phone = "01066666666"
      expect(lead).to be_valid
    end

    it "converts an old lead whose phone breaks the 11-digit rule" do
      lead = create(:lead, created_by: creator, phone: "0105555")
      require_eleven_digits!

      customer = lead.convert!(by: creator)
      expect(customer).to be_persisted
      expect(customer.phone).to eq("0105555")
    end
  end

  describe "exactly 11 digits (company setting)" do
    it "is off by default" do
      expect(new_lead(phone: "0101234567")).to be_valid
    end

    it "refuses 10 or 12 digits on either phone when on" do
      require_eleven_digits!

      expect(new_lead(phone: "0101234567")).not_to be_valid
      expect(new_lead(phone: "010123456789")).not_to be_valid
      lead = new_lead(phone: "01012345678", phone_secondary: "0101234567")
      expect(lead).not_to be_valid
      expect(lead.errors[:phone_secondary]).to include(I18n.t("phones.errors.eleven_digits", field: described_class.human_attribute_name(:phone_secondary)))
      expect(new_lead(phone: "٠١٠١٢٣٤٥٦٧٨")).to be_valid
    end
  end

  describe "existing data" do
    it "saves an old row with a short and duplicated phone when the phone is unchanged" do
      first = create(:lead, created_by: creator, phone: "0101111")
      old = create(:lead, created_by: creator, phone: "0109999")
      old.update_columns(phone: first.phone)
      require_eleven_digits!

      old.reload.notes = "still editable"
      expect(old.save).to be(true)
    end

    it "checks the phone once it is changed" do
      old = create(:lead, created_by: creator, phone: "0101111")
      require_eleven_digits!

      expect(old.update(phone: "0102222")).to be(false)
      expect(old.errors[:phone]).to be_present
    end
  end
end
