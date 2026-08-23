# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Vendor invoice delivery billed on the invoice", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { Current.company }
  let(:owner) { create(:user, :owner, company: company) }
  let(:supplier) { Supplier.create!(name: "Fresh Farms", company: company) }
  let(:location) { create(:location, :central_kitchen, company: company) }
  let!(:treasury) do
    Treasury.create!(name: "Main Safe", treasury_type: "safe", balance_cents: 500_000,
      opening_balance_cents: 500_000, is_default: true, company: company)
  end
  let(:category) { IngredientCategory.create!(name: "Produce", position: 1, company: company) }
  let!(:ingredient) do
    Ingredient.create!(name: "Tomatoes", ingredient_category: category, unit: "kg",
      reorder_threshold: 1, cost_per_unit_cents: 250, quantity_on_hand: 0, company: company)
  end

  before { sign_in owner }

  # goods = 10.00, delivery = 50.00
  def post_invoice(on_account:, goods: "10.00", delivery: "50.00", treasury_id: treasury.id)
    post admin_inventory_vendor_invoices_path, params: {
      vendor_invoice: {
        supplier_id: supplier.id, location_id: location.id,
        invoice_date: Date.current, received_on: Date.current,
        freight_amount_dollars: delivery,
        freight_on_account: on_account ? "1" : "0",
        freight_treasury_id: on_account ? nil : treasury_id,
        vendor_invoice_lines_attributes: {
          "0" => { ingredient_id: ingredient.id, quantity: 4, line_total_dollars: goods }
        }
      }
    }
    VendorInvoice.order(:created_at).last
  end

  describe "paid in cash at receive (existing behaviour)" do
    it "keeps delivery out of the invoice total and AP" do
      invoice = post_invoice(on_account: false)

      expect(invoice.total_cents).to eq(1_000)
      expect(invoice.freight_on_account?).to be(false)
      expect(invoice.freight_expense&.amount_cents).to eq(5_000)
      ap = TreasuryTransaction.find_by!(source_record: invoice, kind: "ap_invoice")
      expect(ap.amount_cents).to eq(1_000)
    end
  end

  describe "billed on the invoice" do
    it "adds delivery to the invoice total" do
      invoice = post_invoice(on_account: true)

      expect(invoice.freight_on_account?).to be(true)
      expect(invoice.freight_amount_cents).to eq(5_000)
      expect(invoice.goods_total_cents).to eq(1_000)
      expect(invoice.total_cents).to eq(6_000)
    end

    it "raises supplier AP by the whole amount" do
      invoice = post_invoice(on_account: true)

      ap = TreasuryTransaction.find_by!(source_record: invoice, kind: "ap_invoice")
      expect(ap.amount_cents).to eq(6_000)
    end

    it "creates no cash expense and moves no cash" do
      expect { post_invoice(on_account: true) }.not_to change(Expense, :count)
      expect(treasury.reload.balance_cents).to eq(500_000)
      expect(VendorInvoice.order(:created_at).last.freight_expense).to be_nil
    end

    it "leaves the delivery owed until the invoice is paid" do
      invoice = post_invoice(on_account: true)

      expect(invoice.balance_due_cents).to eq(6_000)
      expect(invoice.payment_status).to eq("unpaid")
    end

    it "splits the journal entry so delivery is not booked as inventory" do
      invoice = post_invoice(on_account: true)
      je = JournalEntry.for_source(invoice).includes(:lines).first
      debits = je.lines.select { |l| l.debit_cents.to_i.positive? }

      # Goods to Purchases, delivery to the delivery account, AP credited in full.
      # Read the delivery code from the category — codes are assigned per company,
      # so hardcoding one only works in whichever database it was written against.
      delivery_code = ExpenseCategory.find_by!(
        name: ExpenseCategory::GOODS_DELIVERY_NAME, company: company
      ).account_code.to_i
      expect(delivery_code).not_to eq(5100)
      expect(debits.map { |l| [l.account_code.to_i, l.debit_cents] })
        .to contain_exactly([5100, 1_000], [delivery_code, 5_000])
      credits = je.lines.select { |l| l.credit_cents.to_i.positive? }
      expect(credits.sum(&:credit_cents)).to eq(6_000)
    end

    it "balances the journal entry" do
      invoice = post_invoice(on_account: true)
      je = JournalEntry.for_source(invoice).includes(:lines).first

      expect(je.lines.sum(&:debit_cents)).to eq(je.lines.sum(&:credit_cents))
    end

    it "needs no treasury" do
      invoice = post_invoice(on_account: true, treasury_id: nil)

      expect(invoice).to be_persisted
      expect(invoice.total_cents).to eq(6_000)
    end

    it "applies the discount to goods only, never delivery" do
      post admin_inventory_vendor_invoices_path, params: {
        vendor_invoice: {
          supplier_id: supplier.id, location_id: location.id,
          invoice_date: Date.current, received_on: Date.current,
          freight_amount_dollars: "50.00", freight_on_account: "1",
          discount_type: "percentage", discount_value: 10,
          vendor_invoice_lines_attributes: {
            "0" => { ingredient_id: ingredient.id, quantity: 4, line_total_dollars: "10.00" }
          }
        }
      }
      invoice = VendorInvoice.order(:created_at).last

      # 1000 goods − 10% = 900, plus 5000 delivery untouched by the discount.
      expect(invoice.goods_total_cents).to eq(900)
      expect(invoice.total_cents).to eq(5_900)
    end
  end

  # The original specs proved the amount persisted but never that the UI read it
  # back. It did not: both views still read the Expense, which is nil for
  # on-account, so the fee looked unsaved and a re-save would have zeroed it.
  describe "reading the saved fee back" do
    it "shows the fee on the invoice page" do
      invoice = post_invoice(on_account: true)

      get admin_inventory_vendor_invoice_path(invoice)

      expect(response.body).to include(format_money_str(5_000))
      expect(response.body).to include(I18n.t("inventory.vendor_invoices.freight_on_account_note"))
      expect(response.body).not_to include(I18n.t("inventory.vendor_invoices.freight_none"))
    end

    it "prefills the fee on the edit form" do
      invoice = post_invoice(on_account: true)

      get edit_admin_inventory_vendor_invoice_path(invoice)

      expect(response.body).to match(/name="vendor_invoice\[freight_amount_dollars\]"[^>]*value="50\.0"/)
        .or match(/value="50\.0"[^>]*name="vendor_invoice\[freight_amount_dollars\]"/)
      expect(response.body).to match(/name="vendor_invoice\[freight_on_account\]"[^>]*checked/)
        .or match(/checked[^>]*name="vendor_invoice\[freight_on_account\]"/)
    end

    it "survives a re-save that leaves the delivery section untouched" do
      invoice = post_invoice(on_account: true)

      # Resubmit exactly what the prefilled edit form would post.
      patch admin_inventory_vendor_invoice_path(invoice), params: {
        vendor_invoice: {
          supplier_id: supplier.id, location_id: location.id,
          invoice_date: invoice.invoice_date, received_on: invoice.received_on,
          freight_amount_dollars: "50.0", freight_on_account: "1",
          vendor_invoice_lines_attributes: {
            "0" => { id: invoice.vendor_invoice_lines.first.id, ingredient_id: ingredient.id,
                     quantity: 4, line_total_dollars: "10.00" }
          }
        }
      }

      invoice.reload
      expect(invoice.freight_amount_cents).to eq(5_000)
      expect(invoice.total_cents).to eq(6_000)
    end

    it "still shows a cash-paid fee, with its treasury" do
      invoice = post_invoice(on_account: false)

      get admin_inventory_vendor_invoice_path(invoice)

      expect(response.body).to include(format_money_str(5_000))
      expect(response.body).to include(treasury.name)
      expect(response.body).not_to include(I18n.t("inventory.vendor_invoices.freight_on_account_note"))
    end

    def format_money_str(cents)
      Money.new(cents).format(locale: I18n.locale, symbol: ApplicationHelper::MONEY_SYMBOL)
    end
  end

  describe "switching an invoice from cash to on account" do
    it "clears the cash expense so no stale outflow is left behind" do
      invoice = post_invoice(on_account: false)
      expect(invoice.freight_expense).to be_present

      patch admin_inventory_vendor_invoice_path(invoice), params: {
        vendor_invoice: {
          supplier_id: supplier.id, location_id: location.id,
          invoice_date: invoice.invoice_date, received_on: invoice.received_on,
          freight_amount_dollars: "50.00", freight_on_account: "1",
          vendor_invoice_lines_attributes: {
            "0" => { id: invoice.vendor_invoice_lines.first.id, ingredient_id: ingredient.id,
                     quantity: 4, line_total_dollars: "10.00" }
          }
        }
      }

      invoice.reload
      expect(invoice.freight_on_account?).to be(true)
      expect(invoice.reload_freight_expense).to be_nil
      expect(invoice.total_cents).to eq(6_000)
    end
  end
end
