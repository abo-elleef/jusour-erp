# frozen_string_literal: true

module Admin
  module Inventory
    class ManufacturingRunsController < BaseController
      include ManufacturingBulkRecording

      before_action :set_run, only: %i[show reverse]

      def index
        authorize_inventory_index!(ManufacturingRun)
        @runs = ManufacturingRun.includes(:manufacturing_template, :user, :location, :reversed_by, manufacturing_template: :output_ingredient)
          .recent
          .limit(100)
      end

      def new
        authorize :production, :create?, policy_class: ProductionPolicy
        load_manufacturing_bulk_sheet
      end

      def create
        authorize :production, :create?, policy_class: ProductionPolicy
        runs = ::Inventory::BulkRunManufacturingService.new(
          user: current_user,
          location: bulk_location,
          occurred_on: bulk_occurred_on,
          default_shelf_life_days: bulk_param(:default_shelf_life_days),
          rows: bulk_row_params
        ).call
        redirect_to admin_inventory_manufacturing_runs_path,
          notice: t("production.success_bulk", count: runs.size, numbers: runs.map(&:run_number).join(", "))
      rescue ::Inventory::BulkRunManufacturingService::Error, ::Inventory::RunManufacturingService::Error => e
        flash.now[:alert] = e.message
        load_manufacturing_bulk_sheet
        render :new, status: :unprocessable_entity
      end

      def show
        authorize_inventory!(:show)
      end

      def reverse
        authorize_inventory!(:update)
        ::Inventory::ReverseManufacturingRunService.new(run: @run, user: current_user).call
        redirect_to admin_inventory_manufacturing_run_path(@run),
          notice: t("flash.manufacturing_run.reversed")
      rescue ::Inventory::ReverseManufacturingRunService::Error => e
        redirect_to admin_inventory_manufacturing_run_path(@run), alert: e.message
      end

      private

      def set_run
        @run = ManufacturingRun.find(params[:id])
        @manufacturing_run = @run
      end
    end
  end
end
