# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Attaching earlier payments to a drawer", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.zone.local(2026, 6, 10, 14, 0, 0)) { example.run } }

  let(:company) { create(:company) }
  let!(:branch) { create(:location, company: company) }
  let!(:other_branch) { create(:location, company: company) }
  let(:manager) { create(:user, :manager, company: company) }
  let(:cashier) { create(:user, company: company, role: "cashier") }
  let!(:till) do
    Treasury.create!(company: company, name: "Till", treasury_type: "cash_drawer",
                     balance_cents: 0, opening_balance_cents: 0)
  end
  let!(:drawer) do
    CashDrawerSession.create!(company: company, user: cashier, treasury: till, location: branch,
                              session_date: Date.current, opening_float_cents: 10_000, status: "open")
  end

  before do
    Current.company = company
    sign_in manager
  end

  def orphan_payment(amount: 5_000, location: branch, at: 3.hours.ago, status: "completed", method: "cash")
    order = create(:order, user: cashier, company: company, location: location, status: "completed")
    create(:payment, order: order, amount_cents: amount, status: status, payment_method: method,
                     processed_by_user: cashier, cash_drawer_session: nil, created_at: at)
  end

  it "lists only unassigned, completed payments from this branch and day" do
    mine = orphan_payment
    wallet = orphan_payment(method: "vodafone_cash")
    insta = orphan_payment(method: "instapay")
    orphan_payment(location: other_branch)
    orphan_payment(at: 2.days.ago)
    orphan_payment(status: "failed")
    orphan_payment(method: "staff_deduction")

    get payments_admin_accounting_cash_drawer_path(drawer)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("payment_#{mine.id}", "payment_#{wallet.id}", "payment_#{insta.id}")
    expect(response.body.scan(/name="payment_ids\[\]"/).size).to eq(3)
  end

  it "brings an earlier Vodafone Cash payment into the drawer's totals without touching expected cash" do
    payment = orphan_payment(amount: 7_500, method: "vodafone_cash")
    before_expected = ::Accounting::CashReconciliationService.new(drawer).compute_expected!
    expect(::Accounting::SessionSalesSummary.for_session(drawer).vodafone_cash_cents).to eq(0)

    patch attach_payments_admin_accounting_cash_drawer_path(drawer), params: { payment_ids: [payment.id] }

    expect(payment.reload.cash_drawer_session).to eq(drawer)
    expect(::Accounting::SessionSalesSummary.for_session(drawer).vodafone_cash_cents).to eq(7_500)
    expect(drawer.reload.expected_cash_cents).to eq(before_expected)
  end

  it "attaches the selected payments and brings them into expected cash" do
    payment = orphan_payment(amount: 5_000)
    before_expected = ::Accounting::CashReconciliationService.new(drawer).compute_expected!

    patch attach_payments_admin_accounting_cash_drawer_path(drawer), params: { payment_ids: [payment.id] }

    expect(payment.reload.cash_drawer_session).to eq(drawer)
    expect(drawer.reload.expected_cash_cents).to eq(before_expected + 5_000)
    expect(AuditLogEntry.where(action: "payment.attached_to_drawer", record_id: payment.id)).to exist
  end

  it "ignores payment ids that are not eligible" do
    foreign = orphan_payment(location: other_branch)

    patch attach_payments_admin_accounting_cash_drawer_path(drawer), params: { payment_ids: [foreign.id] }

    expect(foreign.reload.cash_drawer_session_id).to be_nil
    expect(flash[:alert]).to eq(I18n.t("flash.accounting.drawer_attach_nothing_selected"))
  end

  it "refuses once the drawer has been counted" do
    payment = orphan_payment
    drawer.update!(status: "reconciled", counted_cash_cents: 10_000)

    patch attach_payments_admin_accounting_cash_drawer_path(drawer), params: { payment_ids: [payment.id] }

    expect(payment.reload.cash_drawer_session_id).to be_nil
    expect(flash[:alert]).to eq(I18n.t("flash.accounting.drawer_attach_not_open"))
  end

  it "is closed to a cashier" do
    sign_in cashier

    get payments_admin_accounting_cash_drawer_path(drawer)

    expect(response).not_to have_http_status(:ok)
  end
end
