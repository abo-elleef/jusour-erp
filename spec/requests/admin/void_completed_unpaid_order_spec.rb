# frozen_string_literal: true

require "rails_helper"

# A completed order nobody paid for — a cart left open and swept up by Complete
# all — could not be voided, so it sat on the unpaid list for good. A manager can
# now void it, and voiding takes back everything completing did: the stock, the
# loyalty points and its place in the day's sales.
RSpec.describe "Voiding a completed order that was never paid", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveSupport::Testing::TimeHelpers

  # Mid-day, so "now" and the business date are the same day (see
  # pos_revenue_ledger_spec for why that matters).
  around { |example| travel_to(Time.zone.local(2026, 6, 10, 12, 0, 0)) { example.run } }

  let(:company) { create(:company) }
  let!(:owner) { create(:user, :owner, company: company) }
  let(:manager) { create(:user, :manager, company: company) }
  let(:cashier) { create(:user, company: company, role: "cashier") }
  let!(:branch) { create(:location, company: company, name: "Main Branch") }
  let(:ingredient) { create(:ingredient, company: company) }
  let!(:stock) { create(:ingredient_location, ingredient: ingredient, location: branch, quantity_on_hand: 5) }
  let(:menu_item) { create(:menu_item, company: company) }

  before do
    Current.company = company
    Recipe.create!(menu_item: menu_item, ingredient: ingredient, quantity_used: 0.25)
  end

  # Rung, sent and completed by the cashier, with no payment: what Complete all
  # did to a forgotten cart.
  def completed_order(customer: nil)
    Current.company = company
    order = create(:order, user: cashier, company: company, location: branch, status: "submitted",
                           order_type: "pickup", customer: customer)
    create(:order_item, order: order, menu_item: menu_item, quantity: 2, unit_price_cents: 4_500)
    order.recalculate_totals!
    Orders::CompleteService.call(order)
    order.reload
  end

  def post_day!
    Current.company = company
    Accounting::PostDailySalesJob.perform_now(branch.id, BusinessDay.for(Time.current, location: branch))
    Current.company = company
  end

  def sales_revenue_cents
    JournalEntryLine.joins(:journal_entry)
                    .where(journal_entries: { company_id: company.id },
                           account_code: Accounting::JournalEntryService::SALES_REVENUE_CODE)
                    .sum("credit_cents - debit_cents").to_i
  end

  def on_hand
    stock.reload.quantity_on_hand.to_d
  end

  describe "as a manager" do
    before { sign_in manager }

    it "cancels it and puts its stock back" do
      order = completed_order
      expect(on_hand).to eq(4.5)

      post void_admin_order_path(order), params: { reason: "Forgotten cart" }

      expect(order.reload).to be_cancelled
      expect(on_hand).to eq(5)
      # Net consumption for the order is nothing, which is what the consumption
      # report now sums.
      expect(StockAdjustment.where(ingredient: ingredient, adjustment_type: "consumption").sum(:quantity_delta)).to eq(0)
    end

    it "takes it out of a day that was already posted" do
      kept = completed_order
      create(:payment, order: kept, amount_cents: kept.total_cents, status: "completed", payment_method: "cash")
      voided = completed_order
      post_day!
      expect(sales_revenue_cents).to eq(kept.total_cents + voided.total_cents)

      post void_admin_order_path(voided)

      expect(sales_revenue_cents).to eq(kept.total_cents)
    end

    it "does not post a day that had not been posted yet" do
      order = completed_order

      post void_admin_order_path(order)

      expect(JournalEntry.where(company: company).where("description LIKE ?", "%[daily_sales]%")).to be_empty
    end

    it "takes back the loyalty points the order earned" do
      customer = create(:customer, company: company)
      order = completed_order(customer: customer)
      Loyalty::AwardPointsService.call(order)
      expect(customer.reload.loyalty_points).to be_positive

      post void_admin_order_path(order)

      expect(customer.reload.loyalty_points).to eq(0)
      expect(customer.total_spent_cents).to eq(0)
    end

    it "offers the void on the order page, with what it will do" do
      order = completed_order

      get admin_order_path(order)

      expect(response.body).to include(void_admin_order_path(order))
      expect(response.body).to include(CGI.escapeHTML(I18n.t("admin.orders.void_completed_hint")))
    end

    it "refuses a completed order that was paid — that is a refund" do
      order = completed_order
      create(:payment, order: order, amount_cents: order.total_cents, status: "completed", payment_method: "cash")

      get admin_order_path(order)
      expect(response.body).not_to include(void_admin_order_path(order))

      post void_admin_order_path(order)
      expect(order.reload).to be_completed
      expect(on_hand).to eq(4.5)
    end
  end

  it "is not for a cashier" do
    order = completed_order
    sign_in cashier

    post void_admin_order_path(order)

    expect(order.reload).to be_completed
  end
end
