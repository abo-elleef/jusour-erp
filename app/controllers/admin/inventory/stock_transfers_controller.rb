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
        @lines = @stock_transfer.stock_transfer_lines.includes(ingredient: :ingredient_category).ordered
        @shipments = @stock_transfer.stock_transfer_shipments.ordered
          .includes(stock_transfer_shipment_lines: { stock_transfer_line: { ingredient: :ingredient_category } })
        @current_shipment = @stock_transfer.current_shipment
        @restrict_stock_transfers_to_source = Setting.restrict_stock_transfers_to_source?
        @source_shortage_lines = if @stock_transfer.completed?
          preload_source_ingredient_locations
          @lines.select(&:source_on_hand_short?)
        else
          []
        end
      end

      def new
        @stock_transfer = StockTransfer.new(
          requested_by: current_user,
          from_location_id: params[:from_location_id],
          to_location_id: params[:to_location_id]
        )
        authorize_inventory!(:create)
        apply_template_if_present
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
          stock_transfer_lines_attributes: %i[id ingredient_id quantity_requested quantity_requested_input unit position _destroy]
        )
      end

      # Ship/receive quantities are entered in each line's fixed unit; convert them
      # to the base unit before the (base-only) services. Base-unit lines pass
      # through untouched. Query lines directly so we don't memoize a stale
      # stock_transfer_lines association that fully_fulfilled? later reads.
      def line_quantity_params
        raw = params.fetch(:lines, {}).permit!.to_h
        lines_by_id = StockTransferLine.where(stock_transfer_id: @stock_transfer.id).index_by { |l| l.id.to_s }
        raw.each_with_object({}) do |(line_id, value), converted|
          line = lines_by_id[line_id.to_s]
          converted[line_id] = if line&.unit.present? && value.present?
                                 line.to_base_unit(value).to_s("F")
                               else
                                 value
                               end
        end
      end

      def build_line_items
        @stock_transfer.stock_transfer_lines.build if @stock_transfer.stock_transfer_lines.empty?
      end

      def apply_template_if_present
        return if params[:template_id].blank?

        template = StockTransferTemplate.active.find_by(id: params[:template_id])
        return if template.blank?

        @applied_template = template
        @stock_transfer.from_location_id ||= template.default_from_location_id
        @stock_transfer.to_location_id ||= template.default_to_location_id
        if @stock_transfer.notes.blank? && template.notes.present?
          @stock_transfer.notes = template.notes
        end

        template.stock_transfer_template_lines
          .includes(ingredient: :ingredient_category)
          .ordered
          .sort_by { |l|
            cat = l.ingredient&.ingredient_category
            [cat&.position.to_i, cat&.name.to_s.downcase, l.position.to_i, l.ingredient&.name.to_s.downcase]
          }
          .each_with_index do |line, index|
            qty = line.default_quantity.to_d
            @stock_transfer.stock_transfer_lines.build(
              ingredient: line.ingredient,
              unit: line.unit.presence || line.ingredient.unit,
              quantity_requested_input: qty.positive? ? qty : nil,
              position: index
            )
          end
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
        @ingredients = Ingredient.active.includes(:ingredient_category, :ingredient_units).order(:name)
        @ingredient_available_units = @ingredients.to_h do |i|
          [i.id, i.available_units.map { |u| [helpers.ingredient_unit_label(u), u] }]
        end
        @transfer_templates = StockTransferTemplate.active.ordered.includes(:stock_transfer_template_lines)
        # Ensure association lines used by the form have categories loaded for grouping.
        ActiveRecord::Associations::Preloader.new(
          records: @stock_transfer.stock_transfer_lines.select(&:ingredient_id),
          associations: { ingredient: :ingredient_category }
        ).call
      end

      def preload_source_ingredient_locations
        @stock_transfer.from_location.ingredient_locations.load
      end

      def record_for_policy
        @stock_transfer || super
      end
    end
  end
end
