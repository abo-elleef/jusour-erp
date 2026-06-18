# frozen_string_literal: true

require "rails_helper"

RSpec.describe VendorInvoice, type: :model do
  let(:user) { create(:user) }
  let(:supplier) { Supplier.create!(name: "Fresh Farms", lead_time_days: 2, company: Current.company) }
  let(:location) { create(:location, company: Current.company) }

  describe ".next_invoice_number" do
    it "returns a dated sequence for the company" do
      date = Date.new(2026, 6, 17)
      expect(described_class.next_invoice_number(date: date)).to eq("VI-2026-06-17-0001")

      described_class.create!(
        supplier: supplier,
        user: user,
        location: location,
        invoice_number: "VI-2026-06-17-0001",
        invoice_date: date,
        received_on: date,
        company: Current.company
      )

      expect(described_class.next_invoice_number(date: date)).to eq("VI-2026-06-17-0002")
    end
  end

  describe "invoice number assignment" do
    it "assigns a number on create when blank" do
      invoice = described_class.create!(
        supplier: supplier,
        user: user,
        location: location,
        invoice_date: Date.current,
        received_on: Date.current,
        company: Current.company
      )

      expect(invoice.invoice_number).to match(/\AVI-\d{4}-\d{2}-\d{2}-\d{4}\z/)
    end
  end
end
