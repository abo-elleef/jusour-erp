# frozen_string_literal: true

module Admin
  module Inventory
    class DeliveriesController < BaseController
      before_action :set_purchase_order

      def new
        authorize_inventory!(:receive_delivery)
        @items = @purchase_order.purchase_order_items.includes(:ingredient)
      end

      def create
        authorize_inventory!(:receive_delivery)
        lines = (params[:deliveries] || {}).values.map do |d|
          d.permit(:purchase_order_item_id, :quantity_received, :expires_on, :batch_reference, :discrepancy_notes)
        end
        ::Inventory::ReceiveDeliveryService.new(@purchase_order, lines, current_user).call
        redirect_to admin_inventory_purchase_order_path(@purchase_order), notice: t("flash.delivery.recorded")
      rescue ActiveRecord::RecordInvalid => e
        redirect_to new_admin_inventory_purchase_order_delivery_path(@purchase_order),
                    alert: e.record.errors.full_messages.to_sentence
      end

      private

      def set_purchase_order
        @purchase_order = PurchaseOrder.find(params[:purchase_order_id])
      end

      def record_for_policy
        @purchase_order
      end
    end
  end
end
