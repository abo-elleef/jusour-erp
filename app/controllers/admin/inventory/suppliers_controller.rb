# frozen_string_literal: true

module Admin
  module Inventory
    class SuppliersController < BaseController
      before_action :set_supplier, only: %i[show edit update destroy]

      def index
        authorize_inventory_index!(Supplier)
        @q = Supplier.ransack(params[:q])
        @total_count = Supplier.count
        @active_count = Supplier.where(active: true).count
        @inactive_count = @total_count - @active_count
        @filtered = params[:q].present? && params[:q].to_unsafe_h.values.any?(&:present?)
        @suppliers = @q.result.includes(:supplier_ingredients).order(:name)
      end

      def show
        authorize_inventory!(:show)
        @supplier_ingredients = @supplier.supplier_ingredients.includes(:ingredient)
        @purchase_orders = @supplier.purchase_orders.order(created_at: :desc).limit(10)
        @price_histories = @supplier.supplier_price_histories
          .includes(:ingredient, :recorded_by_user)
          .order(effective_date: :desc)
          .limit(30)
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

      def destroy
        authorize_inventory!(:destroy)
        @supplier.update!(active: false)
        redirect_to admin_inventory_suppliers_path, notice: t("flash.supplier.deactivated")
      end

      private

      def set_supplier
        @supplier = Supplier.find(params[:id])
      end

      def supplier_params
        params.require(:supplier).permit(
          :name, :contact_name, :email, :phone, :address, :lead_time_days, :active
        )
      end
    end
  end
end
