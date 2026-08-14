# frozen_string_literal: true

module Admin
  module Inventory
    class ManufacturingRunsController < BaseController
      before_action :set_run, only: %i[show reverse]

      def index
        authorize_inventory_index!(ManufacturingRun)
        @runs = ManufacturingRun.includes(:manufacturing_template, :user, :location, :reversed_by, manufacturing_template: :output_ingredient)
          .recent
          .limit(100)
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
