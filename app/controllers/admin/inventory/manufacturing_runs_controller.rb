# frozen_string_literal: true

module Admin
  module Inventory
    class ManufacturingRunsController < BaseController
      before_action :set_run, only: :show

      def index
        authorize_inventory_index!(ManufacturingRun)
        @runs = ManufacturingRun.includes(:manufacturing_template, :user, manufacturing_template: :output_ingredient)
          .recent
          .limit(100)
      end

      def show
        authorize_inventory!(:show)
      end

      private

      def set_run
        @run = ManufacturingRun.find(params[:id])
        @manufacturing_run = @run
      end
    end
  end
end
