# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Fixed asset purchase accounting", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { Current.company }
  let(:owner) { create(:user, :owner, company: company) }
  let!(:safe) do
    Treasury.create!(name: "Main Safe", treasury_type: "safe", balance_cents: 1_000_000,
      opening_balance_cents: 1_000_000, is_default: true, company: company)
  end

  before { sign_in owner }

  def buy(on_credit:, price: "2000.00", treasury: safe)
    post admin_accounting_fixed_assets_path, params: {
      fixed_asset: {
        name: "Dough Mixer", asset_type: "equipment",
        purchase_date: Date.current,
        purchase_price_pounds: price, current_value_pounds: price,
        on_credit: on_credit ? "1" : "0",
        paid_from_treasury_id: on_credit ? nil : treasury.id
      }
    }
    FixedAsset.order(:created_at).last
  end

  describe "paid outright" do
    it "reduces the treasury by the price" do
      expect { buy(on_credit: false) }.to change { safe.reload.balance_cents }.by(-200_000)
    end

    it "records an investing cash movement, not an expense" do
      asset = buy(on_credit: false)
      txn = TreasuryTransaction.find_by!(source_record: asset)

      expect(txn.kind).to eq("fixed_asset_purchase")
      expect(txn.amount_cents).to eq(-200_000)
      expect(TreasuryTransaction.where(kind: "expense", source_record: asset)).to be_empty
    end

    it "needs no separate Expense to move the cash" do
      expect { buy(on_credit: false) }.not_to change(Expense, :count)
    end

    it "debits the asset account and credits cash — never an expense account" do
      asset = buy(on_credit: false)
      je = JournalEntry.for_source(asset).includes(:lines).first

      debit = je.lines.find { |l| l.debit_cents.to_i.positive? }
      expect(debit.account_code.to_i).to eq(1600)          # equipment
      expect(debit.debit_cents).to eq(200_000)
      expect(je.lines.sum(&:debit_cents)).to eq(je.lines.sum(&:credit_cents))
      expect(je.lines.map(&:account_type)).not_to include("expense")
    end

    it "owes nothing" do
      expect(buy(on_credit: false).balance_due_cents).to eq(0)
    end

    it "insists on a treasury" do
      post admin_accounting_fixed_assets_path, params: {
        fixed_asset: { name: "No treasury", asset_type: "equipment",
                       purchase_date: Date.current, purchase_price_pounds: "10.00",
                       current_value_pounds: "10.00", on_credit: "0" }
      }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(FixedAsset.where(name: "No treasury")).to be_empty
    end
  end

  describe "received now, paid later" do
    it "moves no cash at acquisition" do
      expect { buy(on_credit: true) }.not_to change { safe.reload.balance_cents }
    end

    it "credits an equipment payable instead of cash" do
      asset = buy(on_credit: true)
      je = JournalEntry.for_source(asset).includes(:lines).first
      credit = je.lines.find { |l| l.credit_cents.to_i.positive? }

      expect(credit.account_code.to_i).to eq(::Accounting::JournalEntryService::EQUIPMENT_PAYABLE_CODE)
      expect(credit.credit_cents).to eq(200_000)
    end

    it "owes the whole price" do
      asset = buy(on_credit: true)

      expect(asset.amount_paid_cents).to eq(0)
      expect(asset.balance_due_cents).to eq(200_000)
      expect(asset).not_to be_settled
    end
  end

  describe "installments" do
    let(:asset) { buy(on_credit: true) }

    def pay(pounds, treasury: safe)
      post record_payment_admin_accounting_fixed_asset_path(asset), params: {
        fixed_asset_payment: { amount_pounds: pounds, payment_date: Date.current,
                               treasury_id: treasury.id }
      }
      asset.reload
    end

    it "takes cash out of the paying treasury" do
      asset
      expect { pay("500.00") }.to change { safe.reload.balance_cents }.by(-50_000)
    end

    it "reduces the balance due" do
      pay("500.00")

      expect(asset.amount_paid_cents).to eq(50_000)
      expect(asset.balance_due_cents).to eq(150_000)
    end

    it "accumulates across several installments" do
      pay("500.00")
      pay("700.00")
      pay("800.00")

      expect(asset.amount_paid_cents).to eq(200_000)
      expect(asset).to be_settled
    end

    it "posts each installment against the payable, not an expense" do
      pay("500.00")
      payment = asset.fixed_asset_payments.last
      je = JournalEntry.for_source(payment).includes(:lines).first

      debit = je.lines.find { |l| l.debit_cents.to_i.positive? }
      expect(debit.account_code.to_i).to eq(::Accounting::JournalEntryService::EQUIPMENT_PAYABLE_CODE)
      expect(je.lines.map(&:account_type)).not_to include("expense")
      expect(TreasuryTransaction.find_by!(source_record: payment).kind).to eq("fixed_asset_payment")
    end

    it "refuses an installment beyond the balance due" do
      pay("1900.00")

      expect { pay("500.00") }.not_to change { safe.reload.balance_cents }
      expect(asset.reload.amount_paid_cents).to eq(190_000)
      expect(flash[:alert]).to be_present
    end

    it "refuses installments on an asset that was paid outright" do
      outright = buy(on_credit: false)

      post record_payment_admin_accounting_fixed_asset_path(outright), params: {
        fixed_asset_payment: { amount_pounds: "10.00", payment_date: Date.current,
                               treasury_id: safe.id }
      }

      expect(outright.fixed_asset_payments).to be_empty
      expect(flash[:alert]).to eq(I18n.t("accounting.fixed_assets.errors.not_on_credit"))
    end
  end

  describe "cash flow classification" do
    def cash_flow
      # Current.company is per-request; re-establish it to call the service directly.
      Current.company = company
      ::Accounting::CashFlowService.new(start_date: Date.current - 1, end_date: Date.current)
    end

    it "counts an outright purchase once, under investing" do
      buy(on_credit: false)
      cf = cash_flow

      expect(cf.investing.total_cents).to eq(-200_000)
      # The old workaround booked it as an operating expense as well.
      expect(cf.operating.lines.map(&:kind)).not_to include("expense")
    end

    it "shows nothing for a credit purchase until it is paid" do
      buy(on_credit: true)

      expect(cash_flow.investing.total_cents).to eq(0)
    end

    it "shows only the cash actually paid on a credit purchase" do
      asset = buy(on_credit: true)
      post record_payment_admin_accounting_fixed_asset_path(asset), params: {
        fixed_asset_payment: { amount_pounds: "600.00", payment_date: Date.current,
                               treasury_id: safe.id }
      }

      expect(cash_flow.investing.total_cents).to eq(-60_000)
    end
  end
end
