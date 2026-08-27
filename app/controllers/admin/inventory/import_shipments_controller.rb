# frozen_string_literal: true

module Admin
  module Inventory
    class ImportShipmentsController < BaseController
      before_action { require_feature!(:landed_cost) }
      before_action :set_shipment, only: %i[show add_cost remove_cost attach_invoice detach_invoice finalize]

      def index
        authorize_inventory_index!(ImportShipment)
        @pagy, @shipments = pagy(:offset, ImportShipment.recent.includes(:location), limit: 50)
      end

      def new
        authorize_inventory!(:create)
        @shipment = ImportShipment.new(arrival_date: Date.current, location_id: default_location&.id)
        @locations = production_locations
      end

      def create
        authorize_inventory!(:create)
        @shipment = ImportShipment.new(shipment_params)
        @shipment.user = current_user
        @shipment.company ||= Current.company
        if @shipment.save
          redirect_to admin_inventory_import_shipment_path(@shipment), notice: t("inventory.import_shipments.flash.created")
        else
          @locations = production_locations
          render :new, status: :unprocessable_entity
        end
      end

      def show
        authorize_inventory!(:show)
        @preview = ::Inventory::AllocateLandedCostService.new(@shipment).preview
        @linkable_invoices = VendorInvoice.where(import_shipment_id: nil).recent.limit(100)
        @treasuries = Treasury.active.payable.visible_to(current_user).ordered
      end

      def add_cost
        authorize_inventory!(:update)
        treasury = Treasury.active.payable.visible_to(current_user).find_by(id: params[:treasury_id])
        ::Inventory::RecordShipmentCostService.new(
          shipment: @shipment, user: current_user, cost_type: params[:cost_type],
          amount_cents: (params[:amount].to_f * 100).round, treasury: treasury,
          incurred_on: parse_date(params[:incurred_on]) || Date.current, description: params[:description].presence
        ).call
        redirect_to admin_inventory_import_shipment_path(@shipment), notice: t("inventory.import_shipments.flash.cost_added")
      rescue ::Inventory::RecordShipmentCostService::Error => e
        redirect_to admin_inventory_import_shipment_path(@shipment), alert: e.message
      end

      def remove_cost
        authorize_inventory!(:update)
        @shipment.shipment_costs.find_by(id: params[:cost_id])&.destroy
        redirect_to admin_inventory_import_shipment_path(@shipment), notice: t("inventory.import_shipments.flash.cost_removed")
      end

      def attach_invoice
        authorize_inventory!(:update)
        invoice = VendorInvoice.where(import_shipment_id: nil).find_by(id: params[:vendor_invoice_id])
        invoice&.update(import_shipment: @shipment)
        redirect_to admin_inventory_import_shipment_path(@shipment), notice: t("inventory.import_shipments.flash.invoice_attached")
      end

      def detach_invoice
        authorize_inventory!(:update)
        @shipment.vendor_invoices.find_by(id: params[:vendor_invoice_id])&.update(import_shipment: nil)
        redirect_to admin_inventory_import_shipment_path(@shipment), notice: t("inventory.import_shipments.flash.invoice_detached")
      end

      def finalize
        authorize_inventory!(:update)
        ::Inventory::AllocateLandedCostService.new(@shipment, overrides: override_params).finalize!
        redirect_to admin_inventory_import_shipment_path(@shipment), notice: t("inventory.import_shipments.flash.finalized")
      end

      private

      def set_shipment
        @shipment = ImportShipment.find(params[:id])
      end

      # { "<batch_id>" => "<pounds>" } from the preview override inputs → cents.
      def override_params
        (params[:overrides] || {}).each_with_object({}) do |(batch_id, pounds), acc|
          acc[batch_id] = (pounds.to_f * 100).round if pounds.present?
        end
      end

      def production_locations
        Location.active.ordered
      end

      def default_location
        Location.active.central_kitchens.ordered.first || Location.active.ordered.first
      end

      def parse_date(raw)
        return if raw.blank?

        Date.parse(raw.to_s)
      rescue ArgumentError
        nil
      end

      def shipment_params
        params.require(:import_shipment).permit(:location_id, :arrival_date, :notes)
      end
    end
  end
end
