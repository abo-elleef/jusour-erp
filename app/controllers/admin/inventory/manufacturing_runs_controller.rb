# frozen_string_literal: true

module Admin
  module Inventory
    class ManufacturingRunsController < BaseController
      before_action { require_feature!(:manufacturing) }
      include ManufacturingBulkRecording

      before_action :set_run, only: %i[show reverse]

      def index
        authorize_inventory_index!(ManufacturingRun)
        @view = params[:view].to_s == "daily" ? "daily" : "runs"

        if @view == "daily"
          load_daily_view
        else
          @runs = ManufacturingRun.includes(:manufacturing_template, :user, :location, :reversed_by, manufacturing_template: :output_ingredient)
            .recent
            .limit(100)
        end
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

      def load_daily_view
        @day = parse_daily_date(params[:date])
        # Opt in to listing every template, so a printed sheet doubles as a
        # checklist of what could have been made rather than only what was.
        @include_all_templates = params[:include_all] == "1"
        day_runs = ManufacturingRun
          .where(occurred_on: @day, reversed_at: nil)
          .includes(:location, :user, manufacturing_template: [:yield_unit_ref, { output_ingredient: :ingredient_units }])
          .recent
        @daily_rows = ::Inventory::DailyProductionSummaryService.new(
          runs: day_runs,
          templates: (@include_all_templates ? all_active_templates : nil)
        ).call
      end

      def all_active_templates
        ManufacturingTemplate.active
          .includes(:yield_unit_ref, output_ingredient: :ingredient_units)
      end

      def parse_daily_date(raw)
        day = begin
          Date.parse(raw.to_s)
        rescue ArgumentError, TypeError
          Date.current
        end
        [day, Date.current].min
      end

      def set_run
        @run = ManufacturingRun.find(params[:id])
        @manufacturing_run = @run
      end
    end
  end
end
