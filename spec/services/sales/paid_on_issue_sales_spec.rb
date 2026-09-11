# frozen_string_literal: true

require "rails_helper"

# The distribution vertical sells everything through the customer invoice, including
# to walk-in doctors who pay at the counter. A sale settled on the spot must never
# become a receivable, must land in the right treasury for the method used, and must
# be counted by the cashier's drawer.
RSpec.describe "Sales paid on issue" do
  let(:company) { create(:company, business_type: "distribution") }
  let(:user) { create(:user, :owner, company: company) }
  let(:location) { create(:location, company: company) }
  let(:category) { create(:ingredient_category, company: company) }
  let!(:ingredient) do
    create(:ingredient, company: company, ingredient_category: category, name: "Composite", unit: "pieces")
  end
  let(:doctor) { create(:customer, company: company, name: "Dr Walk-in", customer_type: "regular") }

  # Every user is given their own cash drawer on creation, and that is where the
  # cash they take belongs.
  let(:drawer) { user.assigned_treasury }
  let!(:wallet) do
    Treasury.create!(company: company, name: "InstaPay", treasury_type: "mobile_wallet",
      balance_cents: 0, opening_balance_cents: 0)
  end

  before { Current.company = company }

  def sell!(method:, cents: 120_000, customer: doctor)
    invoice = CustomerInvoice.new(company: company, customer: customer, user: user,
      location: location, invoice_date: Date.current, payment_method: method)
    invoice.customer_invoice_lines.build(ingredient: ingredient, quantity: 1,
      unit: ingredient.unit, unit_price_cents: cents)
    invoice.save!
    Sales::ConfirmCustomerInvoiceService.new(invoice, user).call
    invoice.reload
  end

  def ledger(code)
    lines = JournalEntryLine.joins(:journal_entry)
      .where(journal_entries: { company_id: company.id }, account_code: code)
    lines.sum(:debit_cents).to_i - lines.sum(:credit_cents).to_i
  end

  describe "a cash sale" do
    it "settles on the spot and never becomes a receivable" do
      invoice = sell!(method: "cash")

      expect(invoice).to be_confirmed
      expect(invoice.payment_status).to eq("paid")
      expect(invoice.amount_paid_cents).to eq(120_000)
      expect(invoice.balance_due_cents).to eq(0)
      expect(doctor.reload.ar_balance_cents).to eq(0)
      expect(doctor.ar_treasury).to be_nil
    end

    it "puts the money in the till and recognises the revenue" do
      sell!(method: "cash")

      expect(drawer.reload.balance_cents).to eq(120_000)
      expect(ledger(Accounting::JournalEntryService::SALES_REVENUE_CODE)).to eq(-120_000)
      expect(ledger(Accounting::JournalEntryService::EQUITY_CODE)).to eq(0)
    end

    it "still deducts the stock" do
      expect { sell!(method: "cash") }.to change(StockAdjustment, :count).by(1)
      expect(StockAdjustment.last.adjustment_type).to eq("customer_sale")
    end

    it "leaves it off the customer's statement of what they owe" do
      sell!(method: "cash")

      expect(CustomerInvoice.outstanding.count).to eq(0)
    end

    it "is ignored by the credit limit — nothing is being extended" do
      doctor.update!(credit_hard_limit_cents: 1_000)

      expect { sell!(method: "cash", cents: 500_000) }
        .not_to raise_error
    end
  end

  describe "a wallet sale" do
    let!(:mapping) do
      PaymentMethodTreasury.create!(company: company, payment_method: "instapay", treasury: wallet)
    end

    it "lands in the treasury the company mapped for that wallet" do
      sell!(method: "instapay")

      expect(wallet.reload.balance_cents).to eq(120_000)
      expect(drawer.reload.balance_cents).to eq(0)
    end

    it "is refused when the wallet has no treasury behind it" do
      mapping.destroy

      expect { sell!(method: "instapay") }
        .to raise_error(Sales::ConfirmCustomerInvoiceService::Error)
    end

    it "rolls back completely when it is refused" do
      mapping.destroy
      expect {
        begin
          sell!(method: "instapay")
        rescue Sales::ConfirmCustomerInvoiceService::Error
          nil
        end
      }.not_to change(StockAdjustment, :count)
      expect(CustomerInvoice.last).to be_draft
    end
  end

  describe "an on-account sale" do
    let(:clinic) { create(:customer, company: company, name: "Clinic", customer_type: "commercial") }

    it "still raises a receivable, unchanged" do
      invoice = sell!(method: "on_account", customer: clinic)

      expect(invoice.payment_status).to eq("unpaid")
      expect(clinic.reload.ar_balance_cents).to eq(120_000)
      expect(invoice.treasury).to be_nil
      expect(drawer.reload.balance_cents).to eq(0)
    end

    it "still honours the hard credit limit" do
      clinic.update!(credit_hard_limit_cents: 1_000)

      expect { sell!(method: "on_account", customer: clinic) }
        .to raise_error(Sales::ConfirmCustomerInvoiceService::CreditBlocked)
    end
  end

  describe "the cashier's drawer" do
    it "expects the counter takings it actually received" do
      session = CashDrawerSession.create!(company: company, user: user, treasury: drawer,
        location: location, session_date: Date.current, opening_float_cents: 10_000,
        status: "open")

      sell!(method: "cash", cents: 40_000)

      summary = Accounting::SessionSalesSummary.for_session(session)
      expect(summary.cash_cents).to eq(40_000)
      expect(summary.expected_cash_cents).to eq(50_000) # float + takings
    end
  end
end
