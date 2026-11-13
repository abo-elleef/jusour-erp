# frozen_string_literal: true

require "rails_helper"

# The safe receives the expected cash at close; the gap to the count becomes a
# document: an Income when over, a voucher to the cashier when short (or an
# Expense once a manager waives it). Whatever happens, the safe ends holding
# exactly what was counted.
RSpec.describe "Cash drawer over/short documents", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.zone.local(2026, 6, 10, 14, 0, 0)) { example.run } }

  let(:company) { create(:company) }
  let!(:branch) { create(:location, company: company, name: "Cafe") }
  let(:owner) { create(:user, :owner, company: company) }
  let(:cashier) { create(:user, company: company, role: "cashier", name: "Sayed") }
  let!(:till) do
    Treasury.create!(company: company, name: "Till", treasury_type: "cash_drawer",
                     balance_cents: 0, opening_balance_cents: 0)
  end
  let!(:safe) do
    Treasury.create!(company: company, name: "Safe", treasury_type: "safe",
                     balance_cents: 0, opening_balance_cents: 0)
  end
  let!(:drawer) do
    CashDrawerSession.create!(company: company, user: cashier, treasury: till, location: branch,
                              session_date: Date.current, opening_float_cents: 10_000, status: "open",
                              deposit_treasury: safe)
  end

  # Float 100 + cash sales 50 → expected 150.
  before do
    Current.company = company
    order = create(:order, user: cashier, company: company, location: branch, status: "completed")
    create(:payment, order: order, amount_cents: 5_000, status: "completed", payment_method: "cash",
                     processed_by_user: cashier, cash_drawer_session_id: drawer.id)
  end

  def close(counted, by: cashier)
    Accounting::CashReconciliationService.new(drawer).reconcile!(counted, by: by)
    drawer.reload
  end

  def account_balance(code)
    lines = JournalEntryLine.joins(:journal_entry)
                            .where(journal_entries: { company_id: company.id }, account_code: code)
    lines.sum(:debit_cents) - lines.sum(:credit_cents)
  end

  def custom_user(key, *permissions)
    role = Role.create!(company: company, name: key.humanize, key: key, permissions: permissions)
    create(:user, company: company, role: "custom", role_id: role.id)
  end

  context "when the count matches" do
    it "banks the expected cash and books nothing else" do
      close(15_000)

      expect(drawer).to have_attributes(variance_cents: 0, variance_documented: true)
      expect(safe.reload.balance_cents).to eq(15_000)
      expect(till.reload.balance_cents).to eq(-10_000) # the open's float leg is not part of this spec
      expect(drawer.variance_incomes).to be_empty
      expect(drawer.shortage_voucher).to be_nil
    end
  end

  context "when the drawer is over" do
    before { close(15_400) }

    it "banks the expected cash and books the extra as an income into the same safe" do
      income = drawer.variance_incomes.sole

      expect(income).to have_attributes(amount_cents: 400, treasury: safe, income_date: Date.current,
                                        is_auto_generated: true, user: cashier)
      expect(income.income_category).to eq(branch.reload.cash_over_income_category)
      expect(safe.reload.balance_cents).to eq(15_400)
    end

    it "describes who, where, when and the two figures" do
      description = drawer.variance_incomes.sole.description

      expect(description).to include("Sayed", "Cafe", "Till")
      expect(description).to include("150.00", "154.00")
    end

    it "clears only the expected cash against sales, so the extra is income once" do
      expect(account_balance(1160)).to eq(-5_000)
      expect(account_balance(income_code = drawer.variance_incomes.sole.income_category.account_code)).to eq(-400)
      expect(income_code).to be_present
    end

    it "uses the branch's overage treasury when one is set" do
      other = Treasury.create!(company: company, name: "Petty", treasury_type: "safe",
                               balance_cents: 0, opening_balance_cents: 0)
      branch.update!(cash_over_treasury: other)
      Accounting::DrawerVarianceDocuments.sync!(drawer.reload, by: owner)

      expect(drawer.variance_incomes.reload.sole.treasury).to eq(other)
      expect(safe.reload.balance_cents).to eq(15_000)
      expect(other.reload.balance_cents).to eq(400)
    end
  end

  context "when the drawer is short" do
    before { close(14_680) }

    it "banks the expected cash and charges the gap to the cashier by voucher" do
      voucher = drawer.shortage_voucher

      expect(voucher).to have_attributes(direction: Voucher::PAYMENT, amount_cents: 320, treasury: safe,
                                         purpose: Voucher::CASH_SHORTAGE, party: cashier,
                                         voucher_date: Date.current)
      expect(voucher.notes).to include("Sayed", "150.00", "146.80")
      expect(safe.reload.balance_cents).to eq(14_680)
    end

    it "lands on the cashier's staff account, like any money given to them" do
      expect(account_balance(cashier.account_code)).to eq(320)
      expect(Voucher.for_staff_month(Date.current)).to include(drawer.shortage_voucher)
    end

    it "cannot be voided on its own from the vouchers list" do
      expect(VoucherPolicy.new(owner, drawer.shortage_voucher).destroy?).to be false
    end

    it "lets a day-close manager waive it into a company expense, and take that back" do
      closer = custom_user("closer", "accounting:day_close", "accounting:view")
      sign_in closer
      voucher = drawer.shortage_voucher

      post waive_shortage_admin_accounting_cash_drawer_path(drawer)

      drawer.reload
      expect(voucher.reload).to be_voided
      expect(drawer.shortage_voucher).to be_nil
      expect(drawer.variance_expenses.sole).to have_attributes(amount_cents: 320, treasury: safe)
      expect(drawer.shortage_waived_by).to eq(closer)
      expect(safe.reload.balance_cents).to eq(14_680)
      expect(account_balance(cashier.account_code)).to eq(0)

      post unwaive_shortage_admin_accounting_cash_drawer_path(drawer)

      drawer.reload
      expect(drawer.variance_expenses).to be_empty
      expect(drawer.shortage_voucher).to be_present.and(have_attributes(amount_cents: 320))
      expect(safe.reload.balance_cents).to eq(14_680)
      expect(account_balance(cashier.account_code)).to eq(320)
    end

    it "does not let the cashier waive their own shortage" do
      expect(CashDrawerSessionPolicy.new(cashier, drawer).waive_shortage?).to be false
    end

    it "keeps the drawer's order window where it was" do
      closed_at = drawer.updated_at
      Accounting::DrawerVarianceDocuments.sync!(drawer, by: owner)

      expect(drawer.reload.updated_at).to eq(closed_at)
    end
  end

  it "takes the documents back off the books when the drawer is reopened" do
    close(14_680)
    voucher = drawer.shortage_voucher
    sign_in owner

    post reopen_admin_accounting_cash_drawer_path(drawer), params: { reason: "Recount" }

    expect(drawer.reload).to have_attributes(status: "open", variance_documented: false, shortage_voucher_id: nil)
    expect(voucher.reload).to be_voided
    expect(safe.reload.balance_cents).to eq(0)
    expect(account_balance(cashier.account_code)).to eq(0)
  end

  it "re-posts a drawer closed before documents the way it was posted: the count goes to the safe" do
    close(15_400)
    Accounting::DrawerVarianceDocuments.remove!(drawer)
    drawer.update_columns(variance_documented: false)
    Accounting::TreasuryLedgerService.sync_drawer_reconcile!(drawer)
    Accounting::TreasuryLedgerService.sync_drawer_deposit!(drawer)
    Accounting::DrawerVarianceDocuments.sync!(drawer, by: owner)

    expect(drawer.variance_incomes.reload).to be_empty
    expect(safe.reload.balance_cents).to eq(15_400)
  end
end
