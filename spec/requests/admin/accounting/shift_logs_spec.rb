# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Accounting::ShiftLogs", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company)  { Current.company }
  let(:owner)    { create(:user, :owner, company: company) }
  let(:cashier)  { create(:user, company: company, role: "cashier") }

  before { sign_in owner }

  def money(cents) = ApplicationController.helpers.format_money(cents)

  # A completed shift: clocked in 3h ago, out 1h ago.
  let!(:shift) do
    ShiftLog.create!(
      user: cashier, company: company,
      clocked_in_at: 3.hours.ago, clocked_out_at: 1.hour.ago,
      hourly_rate_cents: 5000, tips_cents: 2000, status: "completed"
    )
  end

  def completed_order(total_cents:, created_at:, pay: true)
    order = create(:order, user: cashier, company: company, status: "completed",
      subtotal_cents: total_cents, tax_cents: 0, total_cents: total_cents, created_at: created_at)
    create(:order_item, order: order, unit_price_cents: total_cents)
    create(:payment, order: order, amount_cents: total_cents) if pay
    order
  end

  describe "GET /admin/accounting/shift_logs (index)" do
    it "shows the completed-order count and sales total per shift" do
      completed_order(total_cents: 1_000, created_at: 2.hours.ago)
      completed_order(total_cents: 2_000, created_at: 2.hours.ago)
      # outside the shift window → excluded
      completed_order(total_cents: 9_999, created_at: 10.hours.ago)

      get admin_accounting_shift_logs_path(date: BusinessDay.for(shift.clocked_in_at))
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(money(3_000))      # 1000 + 2000 sales
      expect(response.body).not_to include(money(9_999))  # order outside window excluded
    end
  end

  describe "GET /admin/accounting/shift_logs/:id (show)" do
    it "renders the shift detail with orders and money summary" do
      o1 = completed_order(total_cents: 1_000, created_at: 2.hours.ago)
      o2 = completed_order(total_cents: 2_000, created_at: 90.minutes.ago)

      get admin_accounting_shift_log_path(shift)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(cashier.name)
      expect(response.body).to include(admin_order_path(o1))
      expect(response.body).to include(admin_order_path(o2))
      expect(response.body).to include(money(3_000))       # gross sales
      expect(response.body).to include(I18n.t("accounting.shift_logs.show.payment_methods"))
    end

    it "excludes orders placed outside the shift window" do
      inside  = completed_order(total_cents: 1_000, created_at: 2.hours.ago)
      outside = completed_order(total_cents: 5_000, created_at: 10.hours.ago)

      get admin_accounting_shift_log_path(shift)
      expect(response.body).to include(admin_order_path(inside))
      expect(response.body).not_to include(admin_order_path(outside))
    end
  end
end
