# frozen_string_literal: true

require "rails_helper"

# Marking an invoice historical says "a direct AP payment already paid this".
# It must settle the invoice without moving any money, and must never settle
# more than the supplier's AP ledger says has genuinely been paid.
RSpec.describe "Mark invoice historical", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { Current.company }
  let(:owner) { create(:user, :owner, company: company) }
  let(:manager) { create(:user, :manager, company: company) }
  let(:location) { create(:location, company: company) }
  let(:supplier) { Supplier.create!(name: "Fresh Farms", lead_time_days: 2, company: company) }
  let(:ingredient) do
    Ingredient.create!(name: "Tomatoes", unit: "kg", reorder_threshold: 5, quantity_on_hand: 0,
      cost_per_unit_cents: 200, company: company,
      ingredient_category: IngredientCategory.create!(name: "Produce", position: 1, company: company))
  end

  def invoice(total_cents, on: Date.current - 5)
    inv = VendorInvoice.new(supplier: supplier, user: owner, location: location,
      invoice_number: "INV-#{total_cents}-#{on.strftime('%m%d')}", invoice_date: on,
      received_on: on, company: company)
    inv.vendor_invoice_lines.build(ingredient: ingredient, quantity: 1, line_total_cents: total_cents)
    inv.save!
    ::Accounting::SupplierApLedgerService.record_invoice!(invoice: inv, user: owner)
    inv
  end

  # Reproduces the real defect: money left the treasury against the supplier's AP
  # balance, so the ledger dropped but the invoice still reads as unpaid.
  def direct_payment!(cents)
    ap = supplier.ap_treasury
    ap.with_lock do
      ap.apply_balance_delta!(-cents)
      TreasuryTransaction.create!(treasury: ap, user: owner, amount_cents: -cents, kind: "ap_payment",
        description: "legacy direct payment", occurred_on: Date.current, company: company,
        balance_after_cents: ap.balance_cents)
    end
  end

  def mark(inv, pounds: nil)
    post mark_historical_admin_inventory_vendor_invoice_path(inv),
      params: pounds ? { amount_pounds: pounds } : {}
  end

  describe "as the owner" do
    before { sign_in owner }

    let!(:old_invoice) { invoice(10_000, on: Date.current - 20) }
    let!(:new_invoice) { invoice(30_000, on: Date.current - 2) }

    context "when a direct payment covered the old invoice exactly" do
      before { direct_payment!(10_000) }

      it "settles it without moving any money" do
        ap_before = supplier.ap_treasury.reload.balance_cents
        expense_before = Expense.count
        txn_before = TreasuryTransaction.count
        je_before = JournalEntry.count

        expect { mark(old_invoice) }
          .to change { old_invoice.reload.historical_settled_cents }.from(0).to(10_000)

        # The cash left when the direct payment was made. Nothing may move now.
        expect(supplier.ap_treasury.reload.balance_cents).to eq(ap_before)
        expect(Expense.count).to eq(expense_before)
        expect(TreasuryTransaction.count).to eq(txn_before)
        expect(JournalEntry.count).to eq(je_before)

        expect(old_invoice.reload.payment_status).to eq("paid")
        expect(old_invoice.balance_due_cents).to be_zero
        expect(old_invoice.historical_settled_by).to eq(owner)
      end

      it "brings the open invoices back in line with the AP ledger" do
        mark(old_invoice)

        open_due = supplier.vendor_invoices.posted.outstanding.sum { |i| i.balance_due_cents }
        expect(open_due).to eq(supplier.ap_treasury.reload.balance_cents)
      end

      it "refuses to mark a second invoice — the ledger says nothing more was paid" do
        mark(old_invoice)
        mark(new_invoice)

        expect(flash[:alert]).to include(I18n.t("inventory.vendor_invoices.historical.errors.nothing_overstated",
          balance: ApplicationController.helpers.format_money(30_000)))
        expect(new_invoice.reload.payment_status).to eq("unpaid")
      end
    end

    context "when a direct payment covered only part of an invoice" do
      before { direct_payment!(4_000) }

      it "caps the amount at what the ledger says was paid" do
        mark(old_invoice) # would settle 10,000, but only 4,000 is overstated

        expect(flash[:alert]).to be_present
        expect(old_invoice.reload.payment_status).to eq("unpaid")
      end

      it "part-settles when given the matching amount, leaving the rest owed" do
        mark(old_invoice, pounds: "40.00")

        expect(old_invoice.reload.payment_status).to eq("partially_paid")
        expect(old_invoice.balance_due_cents).to eq(6_000)

        open_due = supplier.vendor_invoices.posted.outstanding.sum { |i| i.balance_due_cents }
        expect(open_due).to eq(supplier.ap_treasury.reload.balance_cents)
      end
    end

    it "can be undone, putting the balance back" do
      direct_payment!(10_000)
      mark(old_invoice)

      delete mark_historical_admin_inventory_vendor_invoice_path(old_invoice)

      expect(old_invoice.reload.payment_status).to eq("unpaid")
      expect(old_invoice.balance_due_cents).to eq(10_000)
      expect(old_invoice.historical_settled_by).to be_nil
    end

    it "leaves a settled invoice out of what a supplier payment can be applied to" do
      direct_payment!(10_000)
      mark(old_invoice)

      payable = ::Accounting::PaySupplierService.open_invoices_for(supplier.reload)
      expect(payable).to contain_exactly(new_invoice)
    end
  end

  # The case that matters most in practice: an old direct payment covered part of
  # an invoice, and the rest is a live debt to be paid the normal way.
  describe "part historical, part paid normally" do
    before { sign_in owner }

    let!(:inv) { invoice(100_000, on: Date.current - 20) }
    let!(:treasury) do
      Treasury.create!(name: "Safe", treasury_type: "safe", balance_cents: 500_000,
        opening_balance_cents: 500_000, company: company, active: true)
    end

    before { direct_payment!(40_000) }

    it "settles the historical part, leaves the rest owed, and lets it be paid normally" do
      mark(inv, pounds: "400.00")

      expect(inv.reload.payment_status).to eq("partially_paid")
      expect(inv.balance_due_cents).to eq(60_000)
      expect(inv.payable?).to be(true)

      post record_payment_admin_inventory_vendor_invoice_path(inv), params: {
        payment_amount_dollars: "600.00", treasury_id: treasury.id, payment_date: Date.current.to_s
      }

      expect(inv.reload.payment_status).to eq("paid")
      expect(inv.balance_due_cents).to be_zero
      # Only the live half moved money; the historical half was already spent.
      expect(inv.amount_paid_cents).to eq(60_000)
      expect(inv.historical_settled_cents).to eq(40_000)
      expect(treasury.reload.balance_cents).to eq(500_000 - 60_000)
      expect(supplier.ap_treasury.reload.balance_cents).to be_zero
    end

    it "still offers the payment form after the historical part is marked" do
      mark(inv, pounds: "400.00")
      get admin_inventory_vendor_invoice_path(inv, locale: "en")

      expect(response.body).to include(I18n.t("inventory.vendor_invoices.record_payment_heading", locale: :en))
    end

    it "lets more of the same invoice be marked historical later" do
      mark(inv, pounds: "100.00")
      mark(inv, pounds: "300.00")

      expect(inv.reload.historical_settled_cents).to eq(40_000)
      expect(inv.balance_due_cents).to eq(60_000)
    end

    it "caps a top-up at what the ledger still overstates" do
      mark(inv, pounds: "400.00")
      mark(inv, pounds: "100.00") # ledger says nothing more was paid

      expect(flash[:alert]).to be_present
      expect(inv.reload.historical_settled_cents).to eq(40_000)
    end

    it "does not let a normal payment and a historical marking together exceed the invoice" do
      post record_payment_admin_inventory_vendor_invoice_path(inv), params: {
        payment_amount_dollars: "800.00", treasury_id: treasury.id, payment_date: Date.current.to_s
      }
      mark(inv, pounds: "400.00") # only 200.00 of room left on the invoice

      expect(flash[:alert]).to be_present
      expect(inv.reload.balance_due_cents).to eq(20_000)
    end
  end

  describe "as a manager" do
    before do
      sign_in manager
      direct_payment!(10_000)
    end

    let!(:old_invoice) { invoice(10_000, on: Date.current - 20) }

    it "is refused — the action is owner-only" do
      mark(old_invoice)

      expect(response).to have_http_status(:found).or have_http_status(:forbidden)
      expect(old_invoice.reload.payment_status).to eq("unpaid")
    end

    it "is not offered on the invoice page" do
      get admin_inventory_vendor_invoice_path(old_invoice)
      expect(response.body).not_to include(I18n.t("inventory.vendor_invoices.historical.heading"))
    end
  end
end
