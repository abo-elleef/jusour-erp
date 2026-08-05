# frozen_string_literal: true

require "rails_helper"

RSpec.describe VendorInvoice, type: :model do
  let(:user) { create(:user) }
  let(:supplier) { Supplier.create!(name: "Fresh Farms", lead_time_days: 2, company: Current.company) }
  let(:location) { create(:location, company: Current.company) }

  describe "#newer / #older" do
    it "walks invoices in the same newest-first order as the index" do
      older = described_class.create!(
        supplier: supplier, user: user, location: location,
        invoice_date: Date.new(2026, 6, 1), received_on: Date.new(2026, 6, 1),
        company: Current.company
      )
      newer = described_class.create!(
        supplier: supplier, user: user, location: location,
        invoice_date: Date.new(2026, 6, 10), received_on: Date.new(2026, 6, 10),
        company: Current.company
      )

      expect(older.newer).to eq(newer)
      expect(older.older).to be_nil
      expect(newer.older).to eq(older)
      expect(newer.newer).to be_nil
    end
  end

  describe ".next_invoice_number" do
    it "returns a yearly VI sequence for the company" do
      expect(described_class.next_invoice_number(year: 2026)).to eq("VI-2026-00001")

      described_class.create!(
        supplier: supplier,
        user: user,
        location: location,
        invoice_number: "VI-2026-00001",
        invoice_date: Date.new(2026, 6, 17),
        received_on: Date.new(2026, 6, 17),
        company: Current.company
      )

      expect(described_class.next_invoice_number(year: 2026)).to eq("VI-2026-00002")
    end

    it "resets the sequence for a new year" do
      described_class.create!(
        supplier: supplier, user: user, location: location,
        invoice_number: "VI-2026-00009",
        invoice_date: Date.new(2026, 1, 1), received_on: Date.new(2026, 1, 1),
        company: Current.company
      )

      expect(described_class.next_invoice_number(year: 2027)).to eq("VI-2027-00001")
    end

    it "ignores legacy dated numbers when starting the yearly series" do
      described_class.create!(
        supplier: supplier, user: user, location: location,
        invoice_number: "VI-2026-07-11-0001",
        invoice_date: Date.new(2026, 7, 11), received_on: Date.new(2026, 7, 11),
        company: Current.company
      )

      expect(described_class.next_invoice_number(year: 2026)).to eq("VI-2026-00001")
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

      expect(invoice.invoice_number).to match(/\AVI-\d{4}-\d{5}\z/)
    end
  end
end
