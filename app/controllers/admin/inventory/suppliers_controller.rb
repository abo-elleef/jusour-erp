# frozen_string_literal: true

module Admin
  module Inventory
    class SuppliersController < BaseController
      before_action :set_supplier, only: %i[show edit update destroy direct_ap_payment]

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

        @invoice_total_cents_by_supplier = VendorInvoice
          .where(supplier_id: supplier_ids)
          .where.not(payment_status: "void")
          .group(:supplier_id)
          .sum(:total_cents)

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

      def show
        authorize_inventory!(:show)
        @supplier_ingredients = @supplier.supplier_ingredients
          .includes(ingredient: :unit_ref)
          .to_a
          .select { |link| link.ingredient.active? }
          .sort_by { |link| [STOCK_RANK.fetch(link.ingredient.stock_status, 3), link.ingredient.name.to_s.downcase] }
        @reorder_count = @supplier_ingredients.count { |link| %i[out low].include?(link.ingredient.stock_status) }
        @vendor_invoices = @supplier.vendor_invoices.order(invoice_date: :desc).limit(10)
        @price_histories = @supplier.supplier_price_histories
          .includes(:ingredient, :recorded_by_user)
          .order(effective_date: :desc)
          .limit(30)
        @ap_transactions = if @supplier.ap_treasury
                             @supplier.ap_treasury.treasury_transactions
                               .where(kind: %w[ap_invoice ap_payment])
                               .order(occurred_on: :desc, created_at: :desc)
                               .limit(50)
                           else
                             TreasuryTransaction.none
                           end
      end

      def new
        @supplier = Supplier.new
        authorize_inventory!(:create)
      end

      def create
        @supplier = Supplier.new(supplier_params)
        authorize_inventory!(:create)
        if @supplier.save
          redirect_to admin_inventory_supplier_path(@supplier), notice: t("flash.supplier.created")
        else
          render :new, status: :unprocessable_entity
        end
      end

      def edit
        authorize_inventory!(:update)
      end

      def update
        authorize_inventory!(:update)
        if @supplier.update(supplier_params)
          redirect_to admin_inventory_supplier_path(@supplier), notice: t("flash.supplier.updated")
        else
          render :edit, status: :unprocessable_entity
        end
      end

      def direct_ap_payment
        authorize_inventory!(:update)
        treasury = Treasury.active.payable.visible_to(current_user).find_by(id: params[:treasury_id])
        amount_cents = (params[:amount_pounds].to_f * 100).round

        ::Accounting::RecordDirectApPaymentService.new(
          supplier:     @supplier,
          user:         current_user,
          treasury:     treasury,
          amount_cents: amount_cents,
          description:  params[:description].presence,
          payment_date: params[:payment_date].presence&.to_date || Date.current
        ).call

        redirect_to admin_inventory_supplier_path(@supplier),
          notice: t("inventory.suppliers.show.direct_ap_payment.success")
      rescue ::Accounting::RecordDirectApPaymentService::Error => e
        redirect_to admin_inventory_supplier_path(@supplier), alert: e.message
      rescue ActiveRecord::RecordNotFound
        redirect_to admin_inventory_supplier_path(@supplier),
          alert: t("inventory.suppliers.show.direct_ap_payment.errors.treasury_required")
      end

      def destroy
        authorize_inventory!(:destroy)

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

      private

      def set_supplier
        @supplier = Supplier.find(params[:id])
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
          :name, :contact_name, :email, :phone, :address, :lead_time_days, :active
        )
      end
    end
  end
end
