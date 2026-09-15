# frozen_string_literal: true

require "rails_helper"

# Delivery used to have a second settlement path — "billed on this invoice", which
# folded the fee into total_cents, raised supplier AP by it, and split the invoice
# journal entry. That option is gone. Delivery is now only ever paid at receive as
# its own expense; delivery the vendor genuinely bills goes in as a line item.
#
# These lock the removal in: the fee never reaches the total, the AP row, or the
# journal entry, and it cannot be recorded without actually paying it.
RSpec.describe "Vendor invoice delivery is never billed on the invoice", type: :request do
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
  def post_invoice(goods: "10.00", delivery: "50.00", treasury_id: treasury.id, extra: {})
    post admin_inventory_vendor_invoices_path, params: {
      vendor_invoice: {
        supplier_id: supplier.id, location_id: location.id,
        invoice_date: Date.current, received_on: Date.current,
        freight_amount_dollars: delivery,
        freight_treasury_id: treasury_id,
        vendor_invoice_lines_attributes: {
          "0" => { ingredient_id: ingredient.id, quantity: 4, line_total_dollars: goods }
        }
      }.merge(extra)
    }
    VendorInvoice.order(:created_at).last
  end

  describe "what the supplier is owed" do
    it "is the goods only — delivery never joins the total" do
      invoice = post_invoice

      expect(invoice.goods_total_cents).to eq(1_000)
      expect(invoice.total_cents).to eq(1_000)
      expect(invoice.balance_due_cents).to eq(1_000)
    end

    it "raises supplier AP by the goods only" do
      invoice = post_invoice

      ap = TreasuryTransaction.find_by!(source_record: invoice, kind: "ap_invoice")
      expect(ap.amount_cents).to eq(1_000)
    end

    it "stays goods-only when a discount is applied" do
      invoice = post_invoice(extra: { discount_type: "percentage", discount_value: 10 })

      # 1000 goods − 10% = 900. The 5000 delivery is settled in cash and is no
      # part of this figure.
      expect(invoice.goods_total_cents).to eq(900)
      expect(invoice.total_cents).to eq(900)
    end
  end

  describe "the journal entry" do
    it "debits the whole total to Purchases, with no delivery split" do
      invoice = post_invoice
      je = JournalEntry.for_source(invoice).includes(:lines).first
      debits = je.lines.select { |l| l.debit_cents.to_i.positive? }

      expect(debits.map { |l| [l.account_code.to_i, l.debit_cents] }).to contain_exactly([5100, 1_000])
      expect(je.lines.sum(&:credit_cents)).to eq(1_000)
    end

    it "balances" do
      invoice = post_invoice
      je = JournalEntry.for_source(invoice).includes(:lines).first

      expect(je.lines.sum(&:debit_cents)).to eq(je.lines.sum(&:credit_cents))
    end

    it "books the delivery on its own expense entry instead" do
      invoice = post_invoice
      freight_je = JournalEntry.for_source(invoice.freight_expense).includes(:lines).first

      delivery_code = ExpenseCategory.find_by!(
        name: ExpenseCategory::GOODS_DELIVERY_NAME, company: company
      ).account_code.to_i
      expect(delivery_code).not_to eq(5100)
      expect(freight_je.lines.select { |l| l.debit_cents.to_i.positive? }
                       .map { |l| [l.account_code.to_i, l.debit_cents] })
        .to contain_exactly([delivery_code, 5_000])
    end
  end

  describe "recording the fee at all" do
    it "always moves the cash — there is no way to defer it to the invoice" do
      expect { post_invoice }.to change(Expense, :count).by(1)
      expect(treasury.reload.balance_cents).to eq(500_000 - 5_000)
    end

    it "is refused without a treasury to pay it from" do
      expect { post_invoice(treasury_id: nil) }.not_to change(VendorInvoice, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include(I18n.t("inventory.vendor_invoices.errors.freight_treasury_required"))
    end
  end

  # The fee is stored on the invoice, not read back off the Expense — a re-save of
  # an untouched delivery section must not zero it.
  describe "reading the saved fee back" do
    it "shows the fee and its treasury on the invoice page" do
      invoice = post_invoice

      get admin_inventory_vendor_invoice_path(invoice)

      expect(response.body).to include(format_money_str(5_000))
      expect(response.body).to include(treasury.name)
      expect(response.body).not_to include(I18n.t("inventory.vendor_invoices.freight_none"))
    end

    it "prefills the fee on the edit form" do
      invoice = post_invoice

      get edit_admin_inventory_vendor_invoice_path(invoice)

      expect(response.body).to match(/name="vendor_invoice\[freight_amount_dollars\]"[^>]*value="50\.0"/)
        .or match(/value="50\.0"[^>]*name="vendor_invoice\[freight_amount_dollars\]"/)
    end

    it "survives a re-save that leaves the delivery section untouched" do
      invoice = post_invoice

      # Resubmit exactly what the prefilled edit form would post.
      patch admin_inventory_vendor_invoice_path(invoice), params: {
        vendor_invoice: {
          supplier_id: supplier.id, location_id: location.id,
          invoice_date: invoice.invoice_date, received_on: invoice.received_on,
          freight_amount_dollars: "50.0", freight_treasury_id: treasury.id,
          vendor_invoice_lines_attributes: {
            "0" => { id: invoice.vendor_invoice_lines.first.id, ingredient_id: ingredient.id,
                     quantity: 4, line_total_dollars: "10.00" }
          }
        }
      }

      invoice.reload
      expect(invoice.freight_amount_cents).to eq(5_000)
      expect(invoice.total_cents).to eq(1_000)
      expect(invoice.freight_expense.amount_cents).to eq(5_000)
    end

    def format_money_str(cents)
      Money.new(cents).format(locale: I18n.locale, symbol: ApplicationHelper::MONEY_SYMBOL)
    end
  end
end
