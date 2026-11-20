# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Drawer closed_at / closed_by" do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.zone.local(2026, 6, 10, 14, 0, 0)) { example.run } }

  let(:company) { create(:company) }
  let!(:branch) { create(:location, company: company) }
  let(:owner) { create(:user, :owner, company: company) }
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
  let!(:drawer) do
    CashDrawerSession.create!(company: company, user: cashier, treasury: till, location: branch,
                              session_date: Date.current, opening_float_cents: 10_000, status: "open",
                              deposit_treasury: safe)
  end

  before { Current.company = company }

  def close(counted = 10_000, by: nil)
    Accounting::CashReconciliationService.new(drawer.reload).reconcile!(counted, by: by)
    drawer.reload
  end

  it "is empty while the drawer is open" do
    expect(drawer).to have_attributes(closed_at: nil, closed_by: nil)
  end

  it "records when and by whom the drawer was closed" do
    close(by: manager)

    expect(drawer.closed_at).to eq(Time.current)
    expect(drawer.closed_by).to eq(manager)
  end

  it "falls back to the drawer's cashier when no closer is given" do
    close

    expect(drawer.closed_by).to eq(cashier)
  end

  it "names the closer, not the cashier, on the audit entry" do
    close(by: manager)

    entry = AuditLogEntry.find_by!(action: "cash_drawer.reconciled", record_id: drawer.id)
    expect(entry.user).to eq(manager)
  end

  it "keeps the first close when the count is corrected later" do
    close(by: cashier)
    first = drawer.closed_at

    travel 30.minutes
    close(9_500, by: manager)

    expect(drawer).to have_attributes(closed_at: first, closed_by: cashier, counted_cash_cents: 9_500)
    expect(drawer.order_window.end).to eq(first)
  end

  it "is cleared by a reopen and set again by the next close" do
    close(by: cashier)
    Accounting::ReopenCashDrawer.call(session: drawer, user: owner, reason: "Miscounted")
    expect(drawer.reload).to have_attributes(closed_at: nil, closed_by: nil)

    travel 10.minutes
    close(by: manager)

    expect(drawer).to have_attributes(closed_at: Time.current, closed_by: manager)
  end
end
