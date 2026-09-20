# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Accounting::Vouchers", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { Current.company }
  let(:owner)   { create(:user, :owner, company: company) }
  let(:cash) do
    Treasury.create!(name: "Cash", treasury_type: "cash_drawer", balance_cents: 100_000,
                     opening_balance_cents: 100_000, company: company)
  end
  let(:category) do
    ExpenseCategory.create!(name: "Rent", category_type: "rent", position: 1, company: company)
  end

  before { sign_in owner }

  # On account: no treasury, so nothing has been paid and a voucher has
  # something to settle.
  def unpaid_expense!(amount_cents: 30_000, date: Date.new(2026, 9, 1))
    Expense.create!(expense_category: category, user: owner, company: company,
                    description: "September rent", amount_cents: amount_cents,
                    expense_date: date)
  end

  describe "GET /admin/accounting/vouchers" do
    it "lists vouchers with both directions" do
      cash
      unpaid_expense!
      ::Accounting::RecordVoucherService.new(
        direction: Voucher::PAYMENT, treasury: cash, user: owner, amount_cents: 5_000
      ).call

      get admin_accounting_vouchers_path(start_date: Date.current.beginning_of_year, end_date: Date.current)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("PV-#{Date.current.year}-00001")
    end

    it "renders when there is nothing to show" do
      get admin_accounting_vouchers_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("accounting.vouchers.empty"))
    end

    it "filters by direction" do
      cash
      ::Accounting::RecordVoucherService.new(direction: Voucher::PAYMENT, treasury: cash,
                                             user: owner, amount_cents: 5_000).call
      ::Accounting::RecordVoucherService.new(direction: Voucher::RECEIPT, treasury: cash,
                                             user: owner, amount_cents: 7_000).call

      get admin_accounting_vouchers_path(direction: Voucher::RECEIPT,
                                         start_date: Date.current.beginning_of_year,
                                         end_date: Date.current)

      expect(response.body).to include("RV-#{Date.current.year}-00001")
      expect(response.body).not_to include("PV-#{Date.current.year}-00001")
    end

    it "exports CSV" do
      cash
      ::Accounting::RecordVoucherService.new(direction: Voucher::PAYMENT, treasury: cash,
                                             user: owner, amount_cents: 5_000).call

      get admin_accounting_vouchers_path(format: :csv,
                                         start_date: Date.current.beginning_of_year,
                                         end_date: Date.current)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("PV-#{Date.current.year}-00001")
    end
  end

  describe "GET /admin/accounting/vouchers/new" do
    it "offers the unpaid expenses a payment voucher could settle" do
      cash
      unpaid_expense!

      get new_admin_accounting_voucher_path(direction: Voucher::PAYMENT)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("September rent")
    end

    it "says so when there is nothing outstanding" do
      cash
      get new_admin_accounting_voucher_path(direction: Voucher::PAYMENT)
      expect(response.body).to include(I18n.t("accounting.vouchers.nothing_unpaid"))
    end

    it "does not offer an expense that was already paid on issue" do
      Expense.create!(expense_category: category, user: owner, company: company,
                      treasury: cash, description: "Fuel paid now",
                      amount_cents: 4_000, expense_date: Date.current)

      get new_admin_accounting_voucher_path(direction: Voucher::PAYMENT)

      expect(response.body).not_to include("Fuel paid now")
    end
  end

  describe "POST /admin/accounting/vouchers" do
    it "issues a payment voucher that settles an unpaid expense" do
      expense = unpaid_expense!(amount_cents: 30_000)

      expect {
        post admin_accounting_vouchers_path, params: {
          voucher: { direction: Voucher::PAYMENT, treasury_id: cash.id,
                     voucher_date: "2026-10-05", amount_pounds: "300.00",
                     counterparty: "Landlord", notes: "Sept rent" },
          settles: "Expense:#{expense.id}"
        }
      }.to change(Voucher, :count).by(1)

      voucher = Voucher.sole
      expect(voucher.voucher_date).to eq(Date.new(2026, 10, 5))
      expect(voucher.amount_cents).to eq(30_000)
      expect(voucher.payment_allocations.sole.settles).to eq(expense)
      expect(cash.reload.balance_cents).to eq(70_000)
      expect(expense.reload.outstanding_cents).to eq(0)
      expect(response).to redirect_to(admin_accounting_voucher_path(voucher))
    end

    it "settles only part of an expense when a smaller amount is given" do
      expense = unpaid_expense!(amount_cents: 30_000)

      post admin_accounting_vouchers_path, params: {
        voucher: { direction: Voucher::PAYMENT, treasury_id: cash.id,
                   voucher_date: Date.current.to_s, amount_pounds: "100.00" },
        settles: "Expense:#{expense.id}", allocation_amount_pounds: "100.00"
      }

      expect(expense.reload.outstanding_cents).to eq(20_000)
    end

    it "records money moved on account when nothing is selected" do
      post admin_accounting_vouchers_path, params: {
        voucher: { direction: Voucher::RECEIPT, treasury_id: cash.id,
                   voucher_date: Date.current.to_s, amount_pounds: "50.00" },
        settles: ""
      }

      voucher = Voucher.sole
      expect(voucher.payment_allocations).to be_empty
      expect(voucher.unallocated_cents).to eq(5_000)
      expect(cash.reload.balance_cents).to eq(105_000)
    end

    it "refuses to settle more than the voucher is worth, and writes nothing" do
      expense = unpaid_expense!(amount_cents: 30_000)

      expect {
        post admin_accounting_vouchers_path, params: {
          voucher: { direction: Voucher::PAYMENT, treasury_id: cash.id,
                     voucher_date: Date.current.to_s, amount_pounds: "50.00" },
          settles: "Expense:#{expense.id}", allocation_amount_pounds: "300.00"
        }
      }.not_to change(Voucher, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(cash.reload.balance_cents).to eq(100_000)
    end
  end

  describe "GET /admin/accounting/vouchers/:id" do
    it "shows the document, what it settled and the entry it wrote" do
      expense = unpaid_expense!
      voucher = ::Accounting::RecordVoucherService.new(
        direction: Voucher::PAYMENT, treasury: cash, user: owner, amount_cents: 30_000,
        counterparty: "Landlord",
        allocations: [{ settles: expense, amount_cents: 30_000 }]
      ).call

      get admin_accounting_voucher_path(voucher)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(voucher.number)
      expect(response.body).to include("Landlord")
      expect(response.body).to include("September rent")
      expect(response.body).to include(JournalEntry.for_source(voucher).sole.entry_number)
    end
  end

  describe "DELETE /admin/accounting/vouchers/:id" do
    it "voids the voucher and gives the money back" do
      expense = unpaid_expense!
      voucher = ::Accounting::RecordVoucherService.new(
        direction: Voucher::PAYMENT, treasury: cash, user: owner, amount_cents: 30_000,
        allocations: [{ settles: expense, amount_cents: 30_000 }]
      ).call
      expect(cash.reload.balance_cents).to eq(70_000)

      # Voided, not destroyed — the document stays in the book.
      expect { delete admin_accounting_voucher_path(voucher) }
        .to change { Voucher.active.count }.by(-1)
        .and change { Voucher.count }.by(0)
      expect(voucher.reload).to be_voided

      expect(cash.reload.balance_cents).to eq(100_000)
      expect(expense.reload.outstanding_cents).to eq(30_000)
      expect(JournalEntry.where(source_record_type: "Voucher", source_record_id: voucher.id)).to be_empty
    end

    it "refuses to void a voucher that only documents history" do
      voucher = Voucher.create!(company: company, direction: Voucher::PAYMENT, treasury: cash,
                                user: owner, amount_cents: 5_000, voucher_date: Date.current,
                                backfilled_at: Time.current)

      delete admin_accounting_voucher_path(voucher)

      expect(Voucher.exists?(voucher.id)).to be(true)
    end
  end
end
