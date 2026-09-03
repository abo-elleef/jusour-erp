# frozen_string_literal: true

module Admin
  class DashboardController < BaseController
    def index
      load_today_stats     if current_user.can?("orders:view")
      load_treasury_stats  if helpers.accounting_any_access?
      load_inventory_stats if helpers.inventory_any_access?
      load_pending_stats   if helpers.inventory_any_access? || current_user.can?("payroll:view")
    end

    private

    def load_today_stats
      today_orders = Order.completed.on_date(Date.current)
      @today_order_count   = today_orders.count
      @today_revenue_cents = today_orders.sum(:total_cents)
      @today_avg_cents     = @today_order_count.positive? ? (@today_revenue_cents / @today_order_count) : 0
    end

    def load_treasury_stats
      @treasuries = ::Treasury.visible_to(current_user).active.ordered.select(:id, :name, :balance_cents, :treasury_type)
      visible = ::Treasury.visible_to(current_user).active
      @default_treasury = visible.find_by(is_default: true) || visible.ordered.first
    end

    def load_inventory_stats
      active = ::Ingredient.active
      @low_stock_count    = active.low_stock.count
      @out_of_stock_count = active.out_of_stock.count
      @no_cost_count      = active.where(cost_per_unit_cents: [nil, 0]).count
    end

    def load_pending_stats
      if helpers.inventory_any_access?
        @open_stock_takes    = ::StockTake.active.count
        @outstanding_invoices = ::VendorInvoice.outstanding.count
      end
      if current_user.can?("payroll:view")
        @payroll_finalized_this_month = ::PayrollSnapshot.for_month(Date.current).exists?
      end
    end
  end
end
