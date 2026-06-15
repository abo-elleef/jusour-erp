# frozen_string_literal: true

module Admin
  module Inventory
    class StockTransfersController < BaseController
      before_action :set_stock_transfer, only: %i[show edit update send_transfer confirm_receipt cancel]

      def index
        authorize_inventory_index!(StockTransfer)
        scope = StockTransfer.includes(:from_location, :to_location, :requested_by, :sent_by, :received_by)
        scope = scope.where(status: params[:status]) if params[:status].present?
        if params[:location_id].present?
          loc_id = params[:location_id]
          scope = scope.where("stock_transfers.from_location_id = ? OR stock_transfers.to_location_id = ?", loc_id, loc_id)
        end
        @stock_transfers = scope.recent.limit(200)
        @locations = Location.active.ordered
        @status_counts = StockTransfer.group(:status).count
      end

      def show
        authorize_inventory!(:show)
        @lines = @stock_transfer.stock_transfer_lines.includes(:ingredient).order("ingredients.name")
        @shipments = @stock_transfer.stock_transfer_shipments.ordered
          .includes(stock_transfer_shipment_lines: { stock_transfer_line: :ingredient })
        @current_shipment = @stock_transfer.current_shipment
      end

      def new
        @stock_transfer = StockTransfer.new(
          requested_by: current_user,
          from_location_id: params[:from_location_id],
          to_location_id: params[:to_location_id]
        )
        authorize_inventory!(:create)
        build_line_items
        load_form_data
      end

      def create
        @stock_transfer = StockTransfer.new(stock_transfer_params)
        @stock_transfer.requested_by = current_user
        authorize_inventory!(:create)

        if save_transfer_with_lines
          redirect_to admin_inventory_stock_transfer_path(@stock_transfer),
            notice: t("flash.stock_transfer.requested")
        else
          build_line_items
          load_form_data
          render :new, status: :unprocessable_entity
        end
      end

      def edit
        authorize_inventory!(:update)
        unless @stock_transfer.editable?
          redirect_to admin_inventory_stock_transfer_path(@stock_transfer),
            alert: t("inventory.stock_transfers.errors.not_editable")
          return
        end
        build_line_items
        load_form_data
      end

      def update
        authorize_inventory!(:update)
        unless @stock_transfer.editable?
          redirect_to admin_inventory_stock_transfer_path(@stock_transfer),
            alert: t("inventory.stock_transfers.errors.not_editable")
          return
        end

        @stock_transfer.assign_attributes(stock_transfer_params)
        if save_transfer_with_lines
          redirect_to admin_inventory_stock_transfer_path(@stock_transfer),
            notice: t("flash.stock_transfer.updated")
        else
          build_line_items
          load_form_data
          render :edit, status: :unprocessable_entity
        end
      end

      def send_transfer
        authorize_inventory!(:update)
        ::Inventory::SendStockTransferService.new(
          @stock_transfer,
          current_user,
          line_quantities: line_quantity_params
        ).call
        redirect_to admin_inventory_stock_transfer_path(@stock_transfer),
          notice: t("flash.stock_transfer.sent")
      rescue ActiveRecord::RecordInvalid => e
        redirect_to admin_inventory_stock_transfer_path(@stock_transfer),
          alert: e.record.errors.full_messages.to_sentence
      end

      def confirm_receipt
        authorize_inventory!(:update)
        ::Inventory::ConfirmStockTransferService.new(
          @stock_transfer,
          current_user,
          line_quantities: line_quantity_params
        ).call
        redirect_to admin_inventory_stock_transfer_path(@stock_transfer),
          notice: t("flash.stock_transfer.received")
      rescue ::Inventory::ConfirmStockTransferService::InsufficientStockError => e
        redirect_to admin_inventory_stock_transfer_path(@stock_transfer), alert: e.message
      rescue ActiveRecord::RecordInvalid => e
        redirect_to admin_inventory_stock_transfer_path(@stock_transfer),
          alert: e.record.errors.full_messages.to_sentence
      end

      def cancel
        authorize_inventory!(:update)
        unless @stock_transfer.requested?
          redirect_to admin_inventory_stock_transfer_path(@stock_transfer),
            alert: t("inventory.stock_transfers.errors.cannot_cancel")
          return
        end

        @stock_transfer.update!(status: "cancelled")
        redirect_to admin_inventory_stock_transfers_path, notice: t("flash.stock_transfer.cancelled")
      end

      private

      def set_stock_transfer
        @stock_transfer = StockTransfer.find(params[:id])
      end

      def stock_transfer_params
        params.require(:stock_transfer).permit(
          :from_location_id, :to_location_id, :notes,
          stock_transfer_lines_attributes: %i[id ingredient_id quantity_requested _destroy]
        )
      end

      def line_quantity_params
        params.fetch(:lines, {}).permit!.to_h
      end

      def build_line_items
        @stock_transfer.stock_transfer_lines.build if @stock_transfer.stock_transfer_lines.empty?
      end

      def save_transfer_with_lines
        active_lines = @stock_transfer.stock_transfer_lines.reject(&:marked_for_destruction?)
        if active_lines.empty?
          @stock_transfer.errors.add(:base, t("inventory.stock_transfers.errors.lines_required"))
          return false
        end

        @stock_transfer.save
      end

      def load_form_data
        @locations = Location.active.ordered
        @ingredients = Ingredient.active.order(:name)
      end

      def record_for_policy
        @stock_transfer || super
      end
    end
  end
end
