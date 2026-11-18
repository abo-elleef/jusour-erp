# frozen_string_literal: true

require "rails_helper"

# Closing a drawer from admin follows the same rule as closing it at the register:
# no open, draft-with-items or unpaid order may be left on it.
RSpec.describe "Closing a cashier's drawer from admin over open or unpaid orders", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let!(:branch) { create(:location, company: company, name: "Main Branch") }
  let(:cashier) { create(:user, company: company, role: "cashier") }
  let(:owner) { create(:user, company: company, role: "owner") }
  let!(:treasury) do
    Treasury.create!(company: company, name: "Front Register", treasury_type: "cash_drawer",
      balance_cents: 50_000, opening_balance_cents: 50_000)
  end
  let(:drawer) { cashier.open_cash_drawer_session(location: branch) }

  before do
    Current.company = company
    cashier.update!(assigned_treasury: treasury)
    sign_in cashier
    post open_drawer_pos_shift_path, params: { opening_float: "100.00" }
    sign_out cashier
    sign_in owner
  end

  def order_for(owner, status: "submitted", with_items: true)
    Current.company = company
    order = create(:order, user: owner, company: company, location: branch, status: status)
    if with_items
      create(:order_item, order: order)
      order.recalculate_totals!
    end
    order
  end

  def pay!(order)
    Current.company = company
    create(:payment, order: order, amount_cents: order.amount_due_cents, status: "completed",
                     payment_method: "instapay")
    order
  end

  it "is refused while an order is still open, and the count page lists it" do
    order = order_for(cashier)

    patch reconcile_admin_accounting_cash_drawer_path(drawer), params: { counted_cash: "100.00" }

    expect(response).to redirect_to(count_admin_accounting_cash_drawer_path(drawer))
    expect(flash[:alert]).to eq(I18n.t("flash.accounting.drawer_has_open_orders", count: 1))
    expect(drawer.reload.status).to eq("open")

    get count_admin_accounting_cash_drawer_path(drawer)
    expect(response.body).to include(admin_order_path(order))
    expect(response.body).not_to include(reconcile_admin_accounting_cash_drawer_path(drawer))
  end

  it "is refused over a draft that has food in it" do
    order_for(cashier, status: "draft")

    patch reconcile_admin_accounting_cash_drawer_path(drawer), params: { counted_cash: "100.00" }

    expect(drawer.reload.status).to eq("open")
  end

  it "is refused over a finished order nobody has paid for" do
    Orders::CompleteService.call(order_for(cashier))

    patch reconcile_admin_accounting_cash_drawer_path(drawer), params: { counted_cash: "100.00" }

    expect(flash[:alert]).to eq(I18n.t("flash.accounting.drawer_has_open_orders", count: 1))
    expect(drawer.reload.status).to eq("open")
  end

  it "counts an open, unpaid order once" do
    order_for(cashier)

    expect(drawer.orders_blocking_close.size).to eq(1)
  end

  it "goes through once every order has an ending and is paid, or is an empty cart" do
    Orders::CompleteService.call(pay!(order_for(cashier)))
    order_for(cashier).update!(status: "cancelled")
    order_for(cashier, status: "draft", with_items: false)

    get count_admin_accounting_cash_drawer_path(drawer)
    expect(response.body).to include(reconcile_admin_accounting_cash_drawer_path(drawer))

    patch reconcile_admin_accounting_cash_drawer_path(drawer), params: { counted_cash: "100.00" }

    expect(response).to redirect_to(admin_accounting_cash_drawer_index_path)
    expect(drawer.reload.status).to eq("reconciled")
  end
end
