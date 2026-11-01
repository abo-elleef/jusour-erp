# frozen_string_literal: true

require "rails_helper"

RSpec.describe Accounting::AgingReportService do
  let(:company) { create(:company, business_type: "distribution") }
  let(:user) { create(:user, company: company, wages_account_code: 2501) }
  let(:location) { create(:location, company: company) }

  before { Current.company = company }

  # Totals are stamped with update_columns: both invoice models recompute their
  # total from lines on save, and these specs only care about the stored balance.
  def customer_invoice!(customer, total:, paid: 0, date:, status: "confirmed")
    invoice = CustomerInvoice.create!(company: company, customer: customer, user: user,
                                      location: location, invoice_date: date)
    payment_status = if paid.zero? then "unpaid" elsif paid >= total then "paid" else "partially_paid" end
    invoice.update_columns(total_cents: total, amount_paid_cents: paid, status: status, payment_status: payment_status)
    invoice
  end

  def vendor_invoice!(supplier, total:, date:, paid: 0, credit: 0, historical: 0, draft: false, void: false)
    invoice = VendorInvoice.create!(company: company, supplier: supplier, user: user, location: location,
                                    invoice_number: "V-#{SecureRandom.hex(3)}", invoice_date: date,
                                    received_on: date, draft: draft)
    settled = paid + credit + historical
    status = if void then "void" elsif settled.zero? then "unpaid" elsif settled >= total then "paid" else "partially_paid" end
    invoice.update_columns(total_cents: total, amount_paid_cents: paid, credit_applied_cents: credit,
                           historical_settled_cents: historical, payment_status: status)
    invoice
  end

  def set_ar_ledger(customer, cents)
    Accounting::CustomerArLedgerService.new(customer).ensure_treasury!.update_columns(balance_cents: cents)
  end

  describe "receivable" do
    let(:customer) { create(:customer, company: company, name: "Clinic", credit_terms_days: 30) }

    it "buckets each open invoice by days past its due date (invoice date + credit terms)" do
      customer_invoice!(customer, total: 70_000, date: 100.days.ago.to_date)          # 70 days late -> 61–90
      customer_invoice!(customer, total: 50_000, paid: 20_000, date: 45.days.ago.to_date) # 15 days late -> 1–30
      customer_invoice!(customer, total: 10_000, date: 10.days.ago.to_date)           # not due yet
      set_ar_ledger(customer, 110_000)

      row = described_class.new(:receivable).call.rows.sole

      expect(row.buckets).to include(not_due: 10_000, days_1_30: 30_000, days_61_90: 70_000, days_90_plus: 0)
      expect(row.invoiced_cents).to eq(110_000)
      expect(row.overdue_cents).to eq(100_000)
      expect(row.oldest_days).to eq(70)
      expect(row.invoice_count).to eq(3)
      expect(row.unallocated_cents).to eq(0)
    end

    it "leaves out drafts, voids, invoices awaiting payment confirmation and paid invoices" do
      customer_invoice!(customer, total: 1_000, date: Date.current, status: "draft")
      customer_invoice!(customer, total: 2_000, date: Date.current, status: "void")
      customer_invoice!(customer, total: 3_000, date: Date.current, status: "pending_payment_confirmation")
      customer_invoice!(customer, total: 4_000, paid: 4_000, date: Date.current)
      customer_invoice!(customer, total: 5_000, date: Date.current)

      expect(described_class.new(:receivable).call.invoiced_cents).to eq(5_000)
    end

    it "lists a customer with a ledger balance but no open invoice, as unallocated" do
      opening = create(:customer, company: company, name: "Opening balance only")
      set_ar_ledger(opening, 8_000)

      row = described_class.new(:receivable).call.rows.find { |r| r.party == opening }

      expect(row.invoiced_cents).to eq(0)
      expect(row.unallocated_cents).to eq(8_000)
    end

    it "keeps only parties with something overdue when asked" do
      late = create(:customer, company: company, name: "Late")
      customer_invoice!(late, total: 9_000, date: 40.days.ago.to_date)
      customer_invoice!(customer, total: 1_000, date: Date.current)

      rows = described_class.new(:receivable, overdue_only: true).call.rows

      expect(rows.map(&:party)).to eq([late])
    end

    it "ignores another company's invoices" do
      customer_invoice!(customer, total: 1_000, date: Date.current)
      other = create(:company, business_type: "distribution")
      Current.company = other
      expect(described_class.new(:receivable).call.rows).to be_empty
    end
  end

  describe "payable" do
    let(:supplier) { Supplier.create!(name: "Mill", lead_time_days: 1, company: company) }

    it "ages from the invoice date and nets payments, credit notes and historical settlements" do
      vendor_invoice!(supplier, total: 100_000, paid: 10_000, credit: 5_000, historical: 5_000, date: 120.days.ago.to_date)
      vendor_invoice!(supplier, total: 30_000, date: 20.days.ago.to_date)
      vendor_invoice!(supplier, total: 9_999, date: Date.current, draft: true)
      vendor_invoice!(supplier, total: 8_888, date: Date.current, void: true)
      supplier.ap_treasury.update_columns(balance_cents: 150_000)

      row = described_class.new(:payable).call.rows.sole

      expect(row.buckets).to include(days_90_plus: 80_000, days_1_30: 30_000, not_due: 0)
      expect(row.invoiced_cents).to eq(110_000)
      expect(row.oldest_days).to eq(120)
      expect(row.ledger_cents).to eq(150_000)
      expect(row.unallocated_cents).to eq(40_000)
    end
  end

  it "rejects an unknown side" do
    expect { described_class.new(:sideways) }.to raise_error(ArgumentError)
  end
end
