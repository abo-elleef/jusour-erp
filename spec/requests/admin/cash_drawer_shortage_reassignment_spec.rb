# frozen_string_literal: true

require "rails_helper"

# A short drawer charges the cashier by voucher at close. The accountant,
# reviewing the day, can move that charge to whoever really handled the cash:
# the voucher is voided and re-issued to them, with a reason on record, and the
# move shows on the shortage moves report.
RSpec.describe "Cash drawer shortage reassignment", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.zone.local(2026, 6, 10, 14, 0, 0)) { example.run } }

  let(:company) { create(:company) }
  let!(:branch) { create(:location, company: company, name: "Cafe") }
  let(:owner) { create(:user, :owner, company: company) }
  let(:cashier) { create(:user, company: company, role: "cashier", name: "Sayed", all_locations: true) }
  let!(:colleague) { create(:user, company: company, role: "cashier", name: "Omar", all_locations: true) }
  let(:accountant) do
    role = Role.create!(company: company, name: "Acc", key: "acc",
                        permissions: %w[accounting:day_close accounting:reassign_shortage payroll:view])
    create(:user, company: company, role: "custom", role_id: role.id, name: "Mona")
  end
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

  # Float 100 + cash sales 50 → expected 150; counted 146.80 → short 3.20.
  before do
    Current.company = company
    order = create(:order, user: cashier, company: company, location: branch, status: "completed")
    create(:payment, order: order, amount_cents: 5_000, status: "completed", payment_method: "cash",
                     processed_by_user: cashier, cash_drawer_session_id: drawer.id)
    Accounting::CashReconciliationService.new(drawer).reconcile!(14_680, by: cashier)
    drawer.reload
  end

  def account_balance(user)
    lines = JournalEntryLine.joins(:journal_entry)
                            .where(journal_entries: { company_id: company.id }, account_code: user.account_code)
    lines.sum(:debit_cents) - lines.sum(:credit_cents)
  end

  def reassign(to: colleague, reason: "Omar worked on Sayed's account in the evening")
    post reassign_shortage_admin_accounting_cash_drawer_path(drawer), params: { to_user_id: to&.id, reason: reason }
    drawer.reload
  end

  it "moves the shortage voucher to the chosen staff member, with the reason on record" do
    sign_in accountant
    old_voucher = drawer.shortage_voucher

    reassign

    new_voucher = drawer.shortage_voucher
    expect(old_voucher.reload).to be_voided
    expect(old_voucher.voided_reason).to eq("drawer_shortage_reassigned")
    expect(old_voucher.replaced_by).to eq(new_voucher)
    expect(new_voucher).to have_attributes(party: colleague, amount_cents: 320, treasury: safe,
                                           purpose: Voucher::CASH_SHORTAGE, voucher_date: Date.current)
    expect(new_voucher.notes).to include("Omar", "Sayed")
    expect(drawer.shortage_charged_to).to eq(colleague)

    move = drawer.shortage_reassignments.sole
    expect(move).to have_attributes(from_user: cashier, to_user: colleague, reassigned_by: accountant,
                                    amount_cents: 320, old_voucher: old_voucher, new_voucher: new_voucher,
                                    reason: "Omar worked on Sayed's account in the evening")
    expect(AuditLogEntry.where(action: "cash_drawer.shortage_reassigned", record_id: drawer.id)).to exist
  end

  it "moves the charge between staff accounts and leaves the safe alone" do
    sign_in accountant
    reassign

    expect(account_balance(cashier)).to eq(0)
    expect(account_balance(colleague)).to eq(320)
    expect(safe.reload.balance_cents).to eq(14_680)
    expect(Voucher.for_staff_month(Date.current).where(party: colleague)).to include(drawer.shortage_voucher)
  end

  it "notifies both staff members" do
    sign_in accountant
    reassign

    expect(Notification.where(recipient: colleague).last.params["message_key"]).to eq("drawer_shortage_moved_to_you")
    expect(Notification.where(recipient: cashier).last.params["message_key"]).to eq("drawer_shortage_moved_off_you")
  end

  it "keeps the charge on the new person through a waive and un-waive" do
    sign_in accountant
    reassign

    post waive_shortage_admin_accounting_cash_drawer_path(drawer)
    expect(account_balance(colleague)).to eq(0)
    post unwaive_shortage_admin_accounting_cash_drawer_path(drawer)

    expect(drawer.reload.shortage_voucher.party).to eq(colleague)
    expect(account_balance(colleague)).to eq(320)
    expect(account_balance(cashier)).to eq(0)
  end

  it "can move it on again, and back to the drawer's cashier" do
    sign_in accountant
    third = create(:user, company: company, role: "cashier", name: "Hany", all_locations: true)
    reassign
    reassign(to: third, reason: "It was Hany after all")
    reassign(to: cashier, reason: "Back to Sayed")

    expect(drawer.shortage_charged_to_id).to be_nil
    expect(drawer.shortage_voucher.party).to eq(cashier)
    expect(drawer.shortage_reassignments.map { |m| [m.from_user, m.to_user] })
      .to contain_exactly([cashier, colleague], [colleague, third], [third, cashier])
    expect([account_balance(cashier), account_balance(colleague), account_balance(third)]).to eq([320, 0, 0])
  end

  it "requires a reason" do
    sign_in accountant
    reassign(reason: "  ")

    expect(drawer.shortage_voucher.party).to eq(cashier)
    expect(drawer.shortage_reassignments).to be_empty
    expect(flash[:alert]).to eq(I18n.t("flash.accounting.drawer_shortage_reassign_failed.reason_required"))
  end

  it "refuses once either person's payroll month is finalized" do
    PayrollSnapshot.create!(company: company, user: colleague, finalized_by: owner,
                            payroll_month: Date.current.beginning_of_month, finalized_at: Time.current)
    sign_in accountant
    reassign

    expect(drawer.shortage_voucher.party).to eq(cashier)
    expect(flash[:alert]).to eq(I18n.t("flash.accounting.drawer_shortage_reassign_failed.payroll_finalized"))
  end

  it "has nothing to move once the shortage is waived" do
    sign_in accountant
    post waive_shortage_admin_accounting_cash_drawer_path(drawer)

    expect(CashDrawerSessionPolicy.new(accountant, drawer.reload).reassign_shortage?).to be false
  end

  it "needs the reassign permission, and never on one's own drawer" do
    day_closer = create(:user, company: company, role: "custom",
                               role_id: Role.create!(company: company, name: "C", key: "c",
                                                     permissions: %w[accounting:day_close]).id)

    expect(CashDrawerSessionPolicy.new(day_closer, drawer).reassign_shortage?).to be false
    expect(CashDrawerSessionPolicy.new(cashier, drawer).reassign_shortage?).to be false
    expect(CashDrawerSessionPolicy.new(accountant, drawer).reassign_shortage?).to be true
  end

  it "starts from the cashier again when the drawer is reopened" do
    sign_in accountant
    reassign
    sign_in owner
    post reopen_admin_accounting_cash_drawer_path(drawer), params: { reason: "Recount" }

    expect(drawer.reload).to have_attributes(status: "open", shortage_charged_to_id: nil, shortage_voucher_id: nil)
    expect(account_balance(colleague)).to eq(0)
    expect(drawer.shortage_reassignments.count).to eq(1)
  end

  it "shows the form and the move on the drawer page" do
    sign_in accountant
    get admin_accounting_cash_drawer_path(drawer)
    expect(response.body).to include(I18n.t("accounting.cash_drawer.variance_docs.reassign"), "Omar")

    reassign
    get admin_accounting_cash_drawer_path(drawer)
    expect(response.body).to include(I18n.t("accounting.cash_drawer.variance_docs.moves_title"),
                                     "Omar worked on Sayed&#39;s account in the evening")
  end

  describe "shortage moves report" do
    before do
      sign_in accountant
      reassign
    end

    it "lists each move with its reason and sums it by person" do
      get admin_accounting_shortage_moves_reports_path(start_date: Date.current.beginning_of_month,
                                                       end_date: Date.current)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Sayed", "Omar", "Mona", "Omar worked on Sayed&#39;s account in the evening",
                                       drawer.shortage_voucher.number)
    end

    it "filters by staff member" do
      get admin_accounting_shortage_moves_reports_path(start_date: Date.current.beginning_of_month,
                                                       end_date: Date.current, user_id: owner.id)

      expect(response.body).to include(I18n.t("accounting.shortage_moves_report.empty"))
    end

    it "is listed on the reports hub" do
      get admin_reports_path
      expect(response.body).to include(I18n.t("accounting.shortage_moves_report.title"))
    end
  end
end
