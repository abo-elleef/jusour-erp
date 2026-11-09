# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Reopening a closed cash drawer", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.zone.local(2026, 6, 10, 14, 0, 0)) { example.run } }

  let(:company) { create(:company) }
  let!(:branch) { create(:location, company: company, name: "Cafe") }
  let(:owner) { create(:user, :owner, company: company) }
  let(:super_manager) { create(:user, company: company, role: "super_manager") }
  let(:manager) { create(:user, :manager, company: company) }
  let(:cashier) { create(:user, company: company, role: "cashier") }
  let!(:till) do
    Treasury.create!(company: company, name: "Till", treasury_type: "cash_drawer",
                     balance_cents: 0, opening_balance_cents: 0)
  end
  let!(:safe) do
    Treasury.create!(company: company, name: "Safe", treasury_type: "safe",
                     balance_cents: 0, opening_balance_cents: 0)
  end

  let(:session_date) { Date.current }
  let!(:drawer) do
    CashDrawerSession.create!(company: company, user: cashier, treasury: till, location: branch,
                              session_date: session_date, opening_float_cents: 10_000, status: "open",
                              deposit_treasury: safe)
  end

  before do
    Current.company = company
    order = create(:order, user: cashier, company: company, location: branch, status: "completed")
    create(:payment, order: order, amount_cents: 5_000, status: "completed", payment_method: "cash",
                     processed_by_user: cashier, cash_drawer_session_id: drawer.id)
    Accounting::CashReconciliationService.new(drawer).reconcile!(15_000)
    till.reload
    safe.reload
  end

  def reopen(reason: "Miscounted the coins")
    post reopen_admin_accounting_cash_drawer_path(drawer), params: { reason: reason }
  end

  it "has been closed, with the cash banked, before we undo it" do
    expect(drawer.reload.status).to eq("reconciled")
    expect(safe.balance_cents).to eq(15_000)
  end

  it "opens the drawer again and takes the close entries back out of the ledger" do
    sign_in owner
    reopen

    expect(response).to redirect_to(admin_accounting_cash_drawer_path(drawer))
    expect(drawer.reload).to have_attributes(status: "open", counted_cash_cents: nil, variance_cents: nil)
    expect(safe.reload.balance_cents).to eq(0)
    expect(till.reload.balance_cents).to eq(0)
    expect(TreasuryTransaction.where(source_record: drawer)).to be_empty
    expect(JournalEntry.unscoped.where(source_record: drawer)).to be_empty
  end

  it "can be counted and closed again afterwards without doubling anything" do
    sign_in owner
    reopen
    Current.company = company # the request leaves it cleared
    Accounting::CashReconciliationService.new(drawer.reload).reconcile!(15_000)

    expect(safe.reload.balance_cents).to eq(15_000)
    expect(drawer.reload.status).to eq("reconciled")
  end

  it "records who reopened it and why" do
    sign_in owner
    reopen(reason: "Miscounted the coins")

    entry = AuditLogEntry.find_by!(action: "cash_drawer.reopened", record_id: drawer.id)
    expect(entry.user).to eq(owner)
    expect(entry.changes_snapshot).to include("reason" => "Miscounted the coins", "counted" => 15_000)
  end

  it "lets a super manager do it too" do
    sign_in super_manager
    reopen
    expect(drawer.reload.status).to eq("open")
  end

  it "refuses a manager, and does not offer them the button" do
    sign_in manager
    get admin_accounting_cash_drawer_path(drawer)
    expect(response.body).not_to include(I18n.t("accounting.cash_drawer.reopen_reason"))

    reopen
    expect(drawer.reload.status).to eq("reconciled")
    expect(flash[:alert]).to eq(I18n.t("flash.accounting.drawer_reopen_forbidden"))
  end

  it "shows the owner the form on a closed drawer" do
    sign_in owner
    get admin_accounting_cash_drawer_path(drawer)
    expect(response.body).to include(I18n.t("accounting.cash_drawer.reopen_reason"))
  end

  it "needs a reason" do
    sign_in owner
    reopen(reason: "  ")

    expect(drawer.reload.status).to eq("reconciled")
    expect(flash[:alert]).to eq(I18n.t("flash.accounting.drawer_reopen_reason_required"))
  end

  it "refuses once the business day has moved on" do
    sign_in owner
    travel 1.day
    reopen

    expect(drawer.reload.status).to eq("reconciled")
    expect(safe.reload.balance_cents).to eq(15_000)
    expect(flash[:alert]).to eq(I18n.t("flash.accounting.drawer_reopen_day_passed"))
  end

  it "refuses when the cashier already opened another drawer today" do
    CashDrawerSession.create!(company: company, user: cashier, treasury: till, location: branch,
                              session_date: session_date, opening_float_cents: 0, status: "open")
    sign_in owner
    reopen

    expect(drawer.reload.status).to eq("reconciled")
    expect(flash[:alert]).to eq(I18n.t("flash.accounting.drawer_reopen_another_open"))
  end

  it "does nothing to a drawer that is already open" do
    Accounting::ReopenCashDrawer.call(session: drawer, user: owner, reason: "first")
    result = Accounting::ReopenCashDrawer.call(session: drawer.reload, user: owner, reason: "again")

    expect(result.success?).to be(false)
    expect(result.error).to eq(:not_closed)
  end
end
