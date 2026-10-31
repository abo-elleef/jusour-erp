# frozen_string_literal: true

module Admin
  module Inventory
    class SuppliersController < BaseController
      before_action :set_supplier,
        only: %i[show edit update destroy purchase_request count_sheet statement]

      SORT_COLUMNS = %w[name contact lead_time ingredients invoice_total outstanding status].freeze

      def index
        authorize_inventory_index!(Supplier)
        @status = %w[active inactive all].include?(params[:status]) ? params[:status] : "active"
        @q = Supplier.ransack(params[:q])
        @total_count = Supplier.count
        @active_count = Supplier.where(active: true).count
        @inactive_count = @total_count - @active_count
        @filtered = (params[:q].present? && params[:q].to_unsafe_h.values.any?(&:present?)) || @status != "active"

        scope = @q.result.includes(:supplier_ingredients, :ap_treasury)
        scope = scope.where(active: true) if @status == "active"
        scope = scope.where(active: false) if @status == "inactive"
        suppliers = scope.to_a
        supplier_ids = suppliers.map(&:id)

        @start_date = params[:start_date].presence&.then { |d| Date.parse(d) rescue nil }
        @end_date   = params[:end_date].presence&.then { |d| Date.parse(d) rescue nil }

        invoice_scope = VendorInvoice
          .where(supplier_id: supplier_ids)
          .where.not(payment_status: "void")
        invoice_scope = invoice_scope.where(invoice_date: @start_date..) if @start_date
        invoice_scope = invoice_scope.where(invoice_date: ..@end_date)   if @end_date

        @invoice_total_cents_by_supplier = invoice_scope
          .group(:supplier_id)
          .sum(:total_cents)
        @date_filtered = @start_date.present? || @end_date.present?

        # When date-filtering, also capture invoices from suppliers not in the
        # current view (e.g. inactive suppliers hidden by the status filter) so
        # the footer total matches the ledger (account 5100).
        if @date_filtered && @status != "all"
          all_invoice_scope = VendorInvoice
            .where(company_id: Current.company.id)
            .where.not(payment_status: "void")
          all_invoice_scope = all_invoice_scope.where(invoice_date: @start_date..) if @start_date
          all_invoice_scope = all_invoice_scope.where(invoice_date: ..@end_date)   if @end_date

          all_total = all_invoice_scope.sum(:total_cents)
          visible_total = @invoice_total_cents_by_supplier.values.sum
          @hidden_suppliers_invoice_cents = all_total - visible_total
        else
          @hidden_suppliers_invoice_cents = 0
        end

        # Same figure as the supplier show page: AP treasury balance (unpaid
        # invoices minus invoice payments and direct AP payments).
        @outstanding_cents_by_supplier = suppliers.to_h { |s| [s.id, s.ap_balance_cents] }

        @sort = SORT_COLUMNS.include?(params[:sort]) ? params[:sort] : "name"
        @direction = params[:dir] == "desc" ? "desc" : "asc"
        # Sort in Ruby so DB columns and computed aggregates (ingredient count,
        # invoice total, outstanding) sort the same way. The list is small.
        suppliers = suppliers.sort_by { |s| [supplier_sort_value(s), s.name.to_s.downcase] }
        suppliers.reverse! if @direction == "desc"
        @suppliers = suppliers
      end

      # Out first, then low, near, ok — so the reorder-worthy items float to the top.
      STOCK_RANK = { out: 0, low: 1, near: 2, ok: 3 }.freeze
      SHOW_INGREDIENT_SORT_COLUMNS = %w[ingredient balance reorder_at max_quantity vendor_product unit_price preferred].freeze

      # The page is a shell (header, stat cards) around one Turbo frame that
      # holds the active tab. The shell request runs only the shell's queries;
      # the frame then fetches the same URL and gets just its tab back. Every
      # link inside the frame (tabs, sorting, filters, paging) swaps the frame
      # alone, so the scroll position never resets, and advances the URL so a
      # reload or a shared link lands on the same tab. A fresh visit with no
      # ?tab= always opens on the overview — the last tab is not remembered.
      TABS = %w[overview ingredients invoices statement price_history].freeze
      TAB_FRAME = "supplier_tab"

      OVERVIEW_LIST_SIZE = 5

      INVOICE_SORTS = {
        "number" => "vendor_invoices.invoice_number",
        "date" => "vendor_invoices.invoice_date",
        "total" => "vendor_invoices.total_cents",
        "status" => "vendor_invoices.payment_status"
      }.freeze
      INVOICE_STATUS_FILTERS = %w[open paid void].freeze

      def show
        authorize_inventory!(:show)
        @tab = TABS.include?(params[:tab]) ? params[:tab] : TABS.first

        if turbo_frame_request_id == TAB_FRAME
          send(:"load_#{@tab}_tab")
          # The admin layout is set explicitly, which overrides turbo-rails'
          # automatic frame layout — without this every tab would render the
          # whole sidebar shell only for Turbo to throw it away.
          render "tab", layout: "turbo_rails/frame"
        else
          load_shell_stats
        end
      end

      # Standalone, printable statement of account. The statement tab renders
      # the same partial; this page exists to print or send to the supplier.
      def statement
        authorize_inventory!(:show)
        load_statement
      end

      def new
        @supplier = Supplier.new
        authorize_inventory!(:manage_settings)
      end

      def create
        @supplier = Supplier.new(supplier_params)
        authorize_inventory!(:manage_settings)
        if @supplier.save
          redirect_to admin_inventory_supplier_path(@supplier), notice: t("flash.supplier.created")
        else
          render :new, status: :unprocessable_entity
        end
      end

      def edit
        authorize_inventory!(:manage_settings)
      end

      def update
        authorize_inventory!(:manage_settings)
        if @supplier.update(supplier_params)
          redirect_to admin_inventory_supplier_path(@supplier), notice: t("flash.supplier.updated")
        else
          render :edit, status: :unprocessable_entity
        end
      end

      def destroy
        authorize_inventory!(:manage_settings)

        unless @supplier.deletable?
          redirect_to admin_inventory_supplier_path(@supplier), alert: t("flash.supplier.cannot_delete")
          return
        end

        ActiveRecord::Base.transaction do
          treasury = @supplier.ap_treasury
          @supplier.destroy!   # removes the FK reference from suppliers -> treasuries
          treasury&.destroy!   # the now-unreferenced, empty AP treasury
        end
        redirect_to admin_inventory_suppliers_path, notice: t("flash.supplier.deleted")
      end

      def purchase_request
        authorize_inventory!(:show)
        load_stock_location_filter
        @lines = ::Inventory::SupplierPurchaseRequestService.new(
          supplier: @supplier,
          location: @stock_location
        ).call
        @estimated_total_cents = @lines.filter_map(&:estimated_cents).sum

        respond_to do |format|
          format.html
          format.csv { send_purchase_request_csv }
        end
      end

      # Printable blind count sheet for a physical stocktake. Deliberately separate
      # from StockTake: only one take can be active per location, so a manager who
      # wants several vendors' sheets in hand can't open a take for each. Printing
      # here commits nothing — the counts get typed into a take afterwards.
      def count_sheet
        authorize_inventory!(:show)
        load_stock_location_filter
        # Blind by default: showing the expected balance invites confirming the
        # number instead of counting it.
        @show_balance = params[:show_balance] == "1"
        @count_sheet_groups = ::Inventory::CountSheet.new(
          location: @stock_location,
          supplier: @supplier
        ).call
        @count_sheet_row_count = @count_sheet_groups.sum { |_, rows| rows.size }
      end

      private

      def load_shell_stats
        @ingredient_count = active_supplier_ingredients.count
        @invoice_count = @supplier.vendor_invoices.posted.where.not(payment_status: "void").count
      end

      def active_supplier_ingredients
        @supplier.supplier_ingredients.joins(:ingredient).merge(Ingredient.where(active: true))
      end

      def load_overview_tab
        load_pay_supplier
        @recent_invoices = @supplier.vendor_invoices.posted.order(invoice_date: :desc, created_at: :desc)
          .limit(OVERVIEW_LIST_SIZE)

        links = active_supplier_ingredients.includes(ingredient: :unit_ref).to_a
        balances = ingredient_balances_for(links)
        urgent = links.select { |link| %i[out low].include?(balances[link.ingredient_id][:status]) }
        @reorder_count = urgent.size
        @reorder_links = urgent
          .sort_by { |link| [STOCK_RANK.fetch(balances[link.ingredient_id][:status], 3), link.ingredient.name.to_s.downcase] }
          .first(OVERVIEW_LIST_SIZE)
        @ingredient_balances = balances
      end

      def load_ingredients_tab
        load_stock_location_filter
        @sort = SHOW_INGREDIENT_SORT_COLUMNS.include?(params[:sort]) ? params[:sort] : nil
        @direction = params[:dir] == "desc" ? "desc" : "asc"

        links = active_supplier_ingredients.includes(ingredient: :unit_ref).to_a
        @ingredient_balances = ingredient_balances_for(links)
        @supplier_ingredients = sort_supplier_ingredients(links)
        @reorder_count = @supplier_ingredients.count do |link|
          %i[out low].include?(@ingredient_balances[link.ingredient_id][:status])
        end
      end

      # Drafts have bought nothing yet, so they belong on the invoices index
      # (where you resume them), not here.
      def load_invoices_tab
        load_pay_supplier
        @invoice_sort = INVOICE_SORTS.key?(params[:sort]) ? params[:sort] : "date"
        @invoice_direction = params[:dir] == "asc" ? "asc" : "desc"
        @invoice_status = INVOICE_STATUS_FILTERS.include?(params[:status]) ? params[:status] : nil

        posted = @supplier.vendor_invoices.posted
        @invoice_status_counts = {
          nil => posted.count,
          "open" => posted.outstanding.count,
          "paid" => posted.where(payment_status: "paid").count,
          "void" => posted.where(payment_status: "void").count
        }

        scope = case @invoice_status
                when "open" then posted.outstanding
                when "paid", "void" then posted.where(payment_status: @invoice_status)
                else posted
                end
        order = Arel.sql("#{INVOICE_SORTS.fetch(@invoice_sort)} #{@invoice_direction.upcase}, vendor_invoices.created_at DESC")
        @invoice_pagy, @invoices = pagy(:offset, scope.order(order), limit: 25)
      end

      def load_statement_tab
        load_statement
      end

      # Price trend for this supplier: paginated and filterable by ingredient, since
      # one supplier can accumulate far more recorded changes than a page can show.
      def load_price_history_tab
        histories = @supplier.supplier_price_histories

        # Options come from what this supplier actually has history for, so the
        # filter never offers an ingredient that would return nothing.
        @price_history_ingredients = Ingredient
          .where(id: histories.select(:ingredient_id))
          .order(:name)

        @price_history_ingredient_id = params[:ph_ingredient_id].presence
        scope = histories
          .includes(:ingredient, :recorded_by_user, vendor_invoice_line: :vendor_invoice)
          .most_recent_first
        scope = scope.where(ingredient_id: @price_history_ingredient_id) if @price_history_ingredient_id

        @price_history_pagy, @price_histories = pagy(:offset, scope, limit: 25)
      end

      # What a payment voucher can land on, in the order it will be applied.
      def load_pay_supplier
        @payable_invoices = ::Accounting::PaySupplierService.open_invoices_for(@supplier)
        @payable_total_cents = @payable_invoices.sum(&:balance_due_cents)
      end

      # URL params only, not the session-shared report range: a statement is
      # per supplier and gets printed or sent, so its range belongs in the link.
      def load_statement
        @statement_start_date = safe_date_param(:start_date) || Date.current.beginning_of_year
        @statement_end_date = safe_date_param(:end_date) || Date.current
        if @statement_start_date > @statement_end_date
          @statement_start_date, @statement_end_date = @statement_end_date, @statement_start_date
        end
        @statement = ::Accounting::SupplierStatementService.new(
          @supplier, start_date: @statement_start_date, end_date: @statement_end_date
        ).call
      end

      def send_purchase_request_csv
        csv = CSV.generate do |out|
          out << [
            t("inventory.suppliers.purchase_request.ingredient"),
            t("inventory.suppliers.purchase_request.code"),
            t("inventory.suppliers.purchase_request.vendor_product"),
            t("inventory.suppliers.purchase_request.vendor_sku"),
            t("inventory.suppliers.purchase_request.unit"),
            t("inventory.suppliers.purchase_request.balance"),
            t("inventory.suppliers.purchase_request.max_quantity"),
            t("inventory.suppliers.purchase_request.requested_qty"),
            t("inventory.suppliers.purchase_request.unit_price"),
            t("inventory.suppliers.purchase_request.estimated")
          ]
          @lines.each do |line|
            link = line.supplier_ingredient
            out << [
              line.ingredient.name,
              line.ingredient.code,
              link.vendor_product_name,
              link.vendor_sku,
              line.display_unit,
              line.balance,
              line.max_quantity,
              line.requested_quantity,
              link.price_cents.to_i.positive? ? (link.price_cents / 100.0) : nil,
              line.estimated_cents ? (line.estimated_cents / 100.0) : nil
            ]
          end
        end

        filename = [
          "purchase-request",
          @supplier.name.parameterize.presence || "supplier",
          (@stock_location&.name&.parameterize),
          Date.current.iso8601
        ].compact.join("-")

        send_data "﻿#{csv}",
          filename: "#{filename}.csv",
          type: "text/csv; charset=utf-8"
      end

      def set_supplier
        @supplier = Supplier.find(params[:id])
      end

      def load_stock_location_filter
        @filter_locations = Location.active.ordered.where(id: current_user.accessible_location_ids)
        @stock_location_id = params[:location_id].to_s
        @stock_location = @filter_locations.find_by(id: @stock_location_id) if @stock_location_id.present?
      end

      # Company-wide ingredient on-hand by default; when a location is chosen,
      # use that location's IngredientLocation qty / reorder / max / stock status.
      def ingredient_balances_for(links)
        if @stock_location
          ils = IngredientLocation
            .where(location_id: @stock_location.id, ingredient_id: links.map(&:ingredient_id))
            .index_by(&:ingredient_id)

          links.each_with_object({}) do |link, memo|
            il = ils[link.ingredient_id]
            source = il || link.ingredient
            memo[link.ingredient_id] = {
              quantity: il&.quantity_on_hand.to_d,
              reorder_at: source.reorder_threshold.to_d,
              max_quantity: source.max_quantity.to_d,
              status: il&.stock_status || :out
            }
          end
        else
          links.each_with_object({}) do |link, memo|
            ing = link.ingredient
            memo[ing.id] = {
              quantity: ing.quantity_on_hand.to_d,
              reorder_at: ing.reorder_threshold.to_d,
              max_quantity: ing.max_quantity.to_d,
              status: ing.stock_status
            }
          end
        end
      end

      def sort_supplier_ingredients(links)
        sorted = links.sort_by { |link| [supplier_ingredient_sort_value(link), link.ingredient.name.to_s.downcase] }
        (@sort.present? && @direction == "desc") ? sorted.reverse : sorted
      end

      # Default (no column clicked): urgency first, then name. Explicit column
      # sorts use that field, with name as a stable tie-breaker.
      def supplier_ingredient_sort_value(link)
        balance = @ingredient_balances[link.ingredient_id]
        case @sort
        when "ingredient"
          link.ingredient.name.to_s.downcase
        when "balance"
          balance[:quantity]
        when "reorder_at"
          balance[:reorder_at]
        when "max_quantity"
          balance[:max_quantity]
        when "vendor_product"
          [link.vendor_product_name, link.vendor_sku].compact_blank.join(" ").downcase
        when "unit_price"
          link.price_cents.to_i
        when "preferred"
          link.preferred? ? 0 : 1
        else
          STOCK_RANK.fetch(balance[:status], 3)
        end
      end

      def supplier_sort_value(supplier)
        case @sort
        when "contact"       then supplier.contact_name.presence&.downcase || supplier.email.to_s.downcase
        when "lead_time"     then supplier.lead_time_days.to_i
        when "ingredients"   then supplier.supplier_ingredients.size
        when "invoice_total" then @invoice_total_cents_by_supplier[supplier.id] || 0
        when "outstanding"   then @outstanding_cents_by_supplier[supplier.id] || 0
        when "status"        then supplier.active? ? 1 : 0
        else                      supplier.name.to_s.downcase
        end
      end

      def supplier_params
        params.require(:supplier).permit(
          :name, :contact_name, :email, :phone, :address, :lead_time_days, :active, :skip_stock_alerts
        )
      end
    end
  end
end
