# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sales::ConfirmCustomerInvoiceService do
  include ActiveJob::TestHelper

  let(:company) { create(:company) }
  let(:user) { create(:user, company: company) }
  let(:location) { create(:location, company: company) }
  let(:category) { create(:ingredient_category, company: company) }
  let(:ingredient) { create(:ingredient, company: company, ingredient_category: category, name: "Implant Kit", unit: "kg") }

  let(:customer) do
    create(:customer, company: company, name: "Bazzar Clinic", customer_type: "commercial",
      credit_warning_limit_cents: 100_000, credit_hard_limit_cents: 150_000)
  end

  before do
    Current.company = company
    StockBatch.create!(ingredient: ingredient, location: location, quantity_received: 100,
      quantity_remaining: 100, cost_per_unit_cents: 1_000, received_on: Date.current)
  end

  def draft_invoice(qty: 5, price_cents: 20_000)
    inv = CustomerInvoice.new(company: company, customer: customer, user: user,
      location: location, invoice_date: Date.current)
    inv.customer_invoice_lines.build(ingredient: ingredient, quantity: qty,
      unit: ingredient.unit, unit_price_cents: price_cents)
    inv.save!
    inv
  end

  it "assigns an SI number and totals the lines" do
    inv = draft_invoice(qty: 5, price_cents: 20_000)
    expect(inv.invoice_number).to match(/\ASI-\d{4}-\d{5}\z/)
    expect(inv.total_cents).to eq(100_000) # 5 × 20,000
  end

  it "confirms: raises AR, deducts stock, and marks the invoice confirmed" do
    inv = draft_invoice(qty: 5, price_cents: 20_000) # total 100,000; at warning limit (=), still ok

    result = described_class.new(inv, user).call

    expect(result.credit_warning).to be(false)
    expect(inv.reload.status).to eq("confirmed")
    expect(inv.confirmed_at).to be_present

    # AR raised on the customer's ledger.
    expect(customer.reload.ar_balance_cents).to eq(100_000)
    expect(customer.total_spent_cents).to eq(100_000)

    # Stock physically deducted at the selling location.
    expect(ingredient.stock_batches.where(location: location).sum(:quantity_remaining).to_d).to eq(95)
    adj = StockAdjustment.find_by(ingredient: ingredient, adjustment_type: "customer_sale")
    expect(adj.quantity_delta.to_d).to eq(-5)

    # A balanced AR journal entry exists (Dr AR / Cr Revenue).
    entry = JournalEntry.where(company: company).order(:created_at).last
    expect(entry.lines.sum(&:debit_cents)).to eq(entry.lines.sum(&:credit_cents))
  end

  it "flags a credit warning but still confirms when over the soft limit" do
    inv = draft_invoice(qty: 6, price_cents: 20_000) # 120,000 > warning 100k, < hard 150k

    result = described_class.new(inv, user).call

    expect(result.credit_warning).to be(true)
    expect(inv.reload.status).to eq("confirmed")
    expect(customer.reload.ar_balance_cents).to eq(120_000)
  end

  it "blocks and changes nothing when over the hard limit" do
    inv = draft_invoice(qty: 8, price_cents: 20_000) # 160,000 > hard 150k

    expect { described_class.new(inv, user).call }
      .to raise_error(Sales::ConfirmCustomerInvoiceService::CreditBlocked)

    expect(inv.reload.status).to eq("draft")               # untouched
    expect(customer.reload.ar_balance_cents).to eq(0)      # no AR raised
    expect(customer.ar_treasury).to be_nil                 # no ledger created
    expect(ingredient.stock_batches.sum(:quantity_remaining).to_d).to eq(100) # stock intact
  end

  it "confirms with no credit limits set (ok regardless of amount)" do
    customer.update!(credit_warning_limit_cents: nil, credit_hard_limit_cents: nil)
    inv = draft_invoice(qty: 50, price_cents: 20_000) # 1,000,000

    result = described_class.new(inv, user).call
    expect(result.credit_warning).to be(false)
    expect(customer.reload.ar_balance_cents).to eq(1_000_000)
  end

  it "rejects confirming a non-draft, empty, or location-less invoice" do
    confirmed = draft_invoice
    described_class.new(confirmed, user).call
    expect { described_class.new(confirmed, user).call }
      .to raise_error(Sales::ConfirmCustomerInvoiceService::Error)
  end

  describe "cash on delivery" do
    let(:shipping_company) { create(:shipping_company, company: company) }

    def cod_invoice
      inv = CustomerInvoice.new(company: company, customer: customer, user: user, location: location,
        invoice_date: Date.current, payment_method: "cash_on_delivery", fulfillment_method: "delivery",
        shipping_company: shipping_company)
      inv.customer_invoice_lines.build(ingredient: ingredient, quantity: 5, unit: ingredient.unit, unit_price_cents: 20_000)
      inv.save!
      inv
    end

    it "confirms (deducting stock) but settles nothing — the shipping company isn't charged until dispatch" do
      inv = cod_invoice
      described_class.new(inv, user).call

      expect(inv.reload.status).to eq("confirmed")
      expect(inv.payment_status).to eq("unpaid")
      expect(inv.treasury).to be_nil
      expect(ingredient.stock_batches.where(location: location).sum(:quantity_remaining).to_d).to eq(95)
      expect(shipping_company.reload.balance_cents).to eq(0)
    end
  end

  describe "online payment (needs approval before it settles)" do
    let(:treasury) do
      Treasury.create!(name: "Bank", treasury_type: "bank", balance_cents: 0, opening_balance_cents: 0, company: company)
    end
    let(:payment_method) { create(:sales_payment_method, company: company, treasury: treasury) }

    def online_invoice
      inv = CustomerInvoice.new(company: company, customer: customer, user: user, location: location,
        invoice_date: Date.current, payment_method: "online", sales_payment_method: payment_method)
      inv.customer_invoice_lines.build(ingredient: ingredient, quantity: 5, unit: ingredient.unit, unit_price_cents: 20_000)
      inv.save!
      inv
    end

    it "parks a draft in pending_payment_confirmation without touching stock or a treasury" do
      inv = online_invoice
      result = described_class.new(inv, user).call

      expect(result.pending_confirmation).to be(true)
      expect(inv.reload.status).to eq("pending_payment_confirmation")
      expect(ingredient.stock_batches.sum(:quantity_remaining).to_d).to eq(100) # untouched
      expect(treasury.reload.balance_cents).to eq(0)
    end

    it "notifies whoever holds sales:confirm_payments when it's submitted" do
      approver = create(:user, company: company, role: "manager")
      inv = online_invoice

      expect { described_class.new(inv, user).call }.to change(Notification, :count).by(1)
      expect(Notification.last.recipient).to eq(approver)
      expect(Notification.last.customer_invoice).to eq(inv)
    end

    it "settles once approved: deducts stock exactly once and banks the money" do
      inv = online_invoice
      described_class.new(inv, user).call # -> pending
      described_class.new(inv, user).call # -> approve (invoice is no longer draft)

      expect(inv.reload.status).to eq("confirmed")
      expect(inv.payment_status).to eq("paid")
      expect(inv.treasury).to eq(treasury)
      expect(treasury.reload.balance_cents).to eq(100_000)
      expect(ingredient.stock_batches.sum(:quantity_remaining).to_d).to eq(95)
    end

    context "when the method requires a payment proof image" do
      let(:payment_method) do
        create(:sales_payment_method, company: company, treasury: treasury, requires_proof_image: true)
      end

      it "refuses to submit a draft for approval without the image, changing nothing" do
        inv = online_invoice

        expect { described_class.new(inv, user).call }
          .to raise_error(Sales::ConfirmCustomerInvoiceService::Error, /#{payment_method.name}/)
        expect(inv.reload.status).to eq("draft")
        expect(StockAdjustment.where(adjustment_type: "customer_sale")).to be_empty
      end

      it "submits once the image is attached" do
        inv = online_invoice
        inv.payment_proof_image.attach(io: File.open(Rails.root.join("spec/fixtures/files/storefront_product.png")),
          filename: "proof.png", content_type: "image/png")

        result = described_class.new(inv, user).call
        expect(result.pending_confirmation).to be(true)
        expect(inv.reload.status).to eq("pending_payment_confirmation")
      end

      it "still approves an invoice that was already pending before the rule" do
        inv = online_invoice
        inv.update!(status: "pending_payment_confirmation")

        described_class.new(inv, user).call
        expect(inv.reload.status).to eq("confirmed")
      end

      it "applies to a method that settles at once too" do
        payment_method.update!(requires_approval: false)
        inv = online_invoice

        expect { described_class.new(inv, user).call }
          .to raise_error(Sales::ConfirmCustomerInvoiceService::Error)
        expect(inv.reload.status).to eq("draft")
      end
    end

    it "does not ask for an image when the method doesn't require one" do
      inv = online_invoice
      expect(payment_method.requires_proof_image).to be(false)

      described_class.new(inv, user).call
      expect(inv.reload.status).to eq("pending_payment_confirmation")
    end

    context "when the method settles at once (card machine)" do
      let(:payment_method) do
        create(:sales_payment_method, company: company, treasury: treasury, requires_approval: false)
      end

      it "settles on the first confirm like cash: no approval queue, no notification" do
        create(:user, company: company, role: "manager") # holds sales:confirm_payments
        inv = online_invoice

        result = nil
        expect { result = described_class.new(inv, user).call }.not_to change(Notification, :count)

        expect(result.pending_confirmation).to be_falsey
        expect(inv.reload.status).to eq("confirmed")
        expect(inv.payment_status).to eq("paid")
        expect(inv.treasury).to eq(treasury)
        expect(treasury.reload.balance_cents).to eq(100_000)
        expect(ingredient.stock_batches.sum(:quantity_remaining).to_d).to eq(95)
      end
    end
  end
end
