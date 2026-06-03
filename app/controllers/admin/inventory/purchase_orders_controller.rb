# frozen_string_literal: true

module Admin
  module Inventory
    class PurchaseOrdersController < BaseController
      before_action :set_purchase_order, only: %i[show edit update destroy send_to_supplier]

      def index
        authorize_inventory_index!(PurchaseOrder)
        @q = PurchaseOrder.ransack(params[:q])
        @filtered = params[:q].present? && params[:q].to_unsafe_h.values.any?(&:present?)
        @purchase_orders = @q.result.includes(:supplier, :user).order(created_at: :desc)
        scope = PurchaseOrder.all
        @total_count = scope.count
        @draft_count = scope.draft.count
        @open_count = scope.where(status: %w[sent partially_received]).count
        @received_count = scope.received.count
        @cancelled_count = scope.cancelled.count
        @suppliers = Supplier.active.order(:name)
      end

      def show
        authorize_inventory!(:show)
        @items = @purchase_order.purchase_order_items.includes(:ingredient)
      end

      def new
        @purchase_order = PurchaseOrder.new(user: current_user)
        authorize_inventory!(:create)
        prefill_from_suggestions if params[:from] == "suggestions" && params[:supplier_id].present?
        @prefilled_from_suggestions = params[:from] == "suggestions" && @purchase_order.purchase_order_items.any? { |i| i.ingredient_id.present? }
        build_line_items
        load_form_data
      end

      def create
        @purchase_order = PurchaseOrder.new(purchase_order_params.merge(user: current_user))
        authorize_inventory!(:create)
        if @purchase_order.save
          redirect_to admin_inventory_purchase_order_path(@purchase_order), notice: t("flash.purchase_order.created")
        else
          @prefilled_from_suggestions = false
          build_line_items
          load_form_data
          render :new, status: :unprocessable_entity
        end
      end

      def edit
        authorize_inventory!(:update)
        build_line_items
        load_form_data
      end

      def update
        authorize_inventory!(:update)
        if @purchase_order.update(purchase_order_params)
          redirect_to admin_inventory_purchase_order_path(@purchase_order), notice: t("flash.purchase_order.updated")
        else
          build_line_items
          load_form_data
          render :edit, status: :unprocessable_entity
        end
      end

      def destroy
        authorize_inventory!(:destroy)
        @purchase_order.cancel! if @purchase_order.may_cancel?
        redirect_to admin_inventory_purchase_orders_path, notice: t("flash.purchase_order.cancelled")
      end

      def send_to_supplier
        authorize_inventory!(:send_po)
        if @purchase_order.may_send_to_supplier?
          @purchase_order.send_to_supplier!
          redirect_to admin_inventory_purchase_order_path(@purchase_order), notice: t("flash.purchase_order.sent")
        else
          redirect_to admin_inventory_purchase_order_path(@purchase_order), alert: t("flash.purchase_order.cannot_send")
        end
      end

      def suggestions
        authorize_inventory_index!(PurchaseOrder)
        @grouped = ::Inventory::SuggestPurchaseOrdersService.new.call
        @skipped_low_stock = Ingredient.active.low_stock
          .includes(:ingredient_category)
          .select { |ingredient| ingredient.supplier_ingredients.none? }
        @line_count = @grouped.values.sum(&:size)
        @estimated_total_cents = @grouped.sum do |_supplier, lines|
          lines.sum { |line| (line[:suggested_quantity].to_d * line[:unit_price_cents]).round }
        end
      end

      private

      def set_purchase_order
        @purchase_order = PurchaseOrder.find(params[:id])
      end

      def prefill_from_suggestions
        supplier = Supplier.find_by(id: params[:supplier_id])
        return unless supplier

        @purchase_order.supplier = supplier
        lines = ::Inventory::SuggestPurchaseOrdersService.new.call[supplier] || []
        lines.each do |line|
          @purchase_order.purchase_order_items.build(
            ingredient_id: line[:ingredient].id,
            quantity_ordered: line[:suggested_quantity],
            unit_price_cents: line[:unit_price_cents]
          )
        end
      end

      def build_line_items
        remaining = 3 - @purchase_order.purchase_order_items.reject(&:marked_for_destruction?).size
        remaining.times { @purchase_order.purchase_order_items.build } if remaining.positive?
      end

      def load_form_data
        @suppliers = Supplier.active.order(:name)
        @ingredients = Ingredient.active.order(:name)
      end

      def purchase_order_params
        permitted = params.require(:purchase_order).permit(
          :supplier_id, :expected_on, :notes,
          purchase_order_items_attributes: %i[id ingredient_id quantity_ordered unit_price_dollars _destroy]
        )
        permitted[:purchase_order_items_attributes]&.each_value do |attrs|
          dollars = attrs.delete(:unit_price_dollars)
          attrs[:unit_price_cents] = (BigDecimal(dollars.to_s.presence || "0") * 100).round
        end
        permitted
      end
    end
  end
end
