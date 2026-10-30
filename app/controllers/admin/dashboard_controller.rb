# frozen_string_literal: true

module Admin
  class DashboardController < BaseController
    def index
      load_today_stats     if current_user.can?("orders:view")
      load_treasury_flow   if helpers.accounting_any_access?
      load_inventory_stats if helpers.inventory_any_access?
      load_pending_stats   if helpers.inventory_any_access? || current_user.can?("payroll:view")
      load_storefront_url  if Current.company.feature_enabled?(:storefront) && current_user.can?("storefront:manage")
    end

    private

    # Only a published site gets a quick link — a draft one would open a 404.
    def load_storefront_url
      storefront = ::Storefront.find_by(enabled: true)
      return unless storefront

      @storefront_url = storefront.public_url(port: request.port) ||
        public_storefront_home_url(company_slug: Current.company.slug)
    end

    def load_today_stats
      today_orders = Order.completed.on_date(Date.current)
      @today_order_count   = today_orders.count
      @today_revenue_cents = today_orders.sum(:total_cents)
      @today_avg_cents     = @today_order_count.positive? ? (@today_revenue_cents / @today_order_count) : 0
    end

def load_treasury_flow
      treasury_ids = ::Treasury.visible_to(current_user).active.pluck(:id)
      today_txns = ::TreasuryTransaction.where(treasury_id: treasury_ids, occurred_on: Date.current)
      @treasury_in_cents  = today_txns.where("amount_cents > 0").sum(:amount_cents)
      @treasury_out_cents = today_txns.where("amount_cents < 0").sum(:amount_cents).abs
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
