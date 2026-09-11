# frozen_string_literal: true

module Admin
  module Inventory
    class StockTransfersController < BaseController
      SORT_COLUMNS = %w[transfer_number transferred_on status from_location to_location requested_by].freeze
      SCOPES = %w[open today all].freeze

      before_action :set_stock_transfer,
        only: %i[show edit update submit destroy send_transfer confirm_receipt cancel
                 close_short void_shipment revert_shipment]

      # Lands on the open work queue rather than the full history: this page is
      # used to act on transfers, and an all-time list grows past scanning.
      def index
        authorize_inventory_index!(StockTransfer)
        @sort      = SORT_COLUMNS.include?(params[:sort].to_s) ? params[:sort].to_s : nil
        @direction = params[:dir].to_s == "asc" ? "asc" : "desc"
        @status    = params[:status].presence_in(StockTransfer::STATUSES)
        # An explicit status tab wins; otherwise fall back to a scope tab.
        @scope_name = @status ? nil : (params[:scope].presence_in(SCOPES) || "open")

        # A drill-down names exactly which transfers it means, so it must not be
        # re-narrowed by the default open-work-queue scope — the report it comes
        # from counts completed transfers, which that scope hides.
        @scope_name = "all" if @status.nil? && drilled_down? && params[:scope].blank?
        @drill_ingredient = Ingredient.find_by(id: params[:ingredient_id]) if params[:ingredient_id].present?

        load_tab_counts
        scope = apply_sort(apply_scope(with_index_associations))
        @pagy, @stock_transfers = pagy(:offset, scope, limit: 50)
        @locations = Location.active.ordered
        load_completed_today if @scope_name == "open"
      end

      def show
        authorize_inventory!(:show)
        # Shipment lines are preloaded because quantity_open_in_transit reads them per
        # line; without this the progress table fires a query per row.
        @lines = @stock_transfer.stock_transfer_lines
          .includes(ingredient: :ingredient_category,
                    stock_transfer_shipment_lines: :stock_transfer_shipment)
          .ordered
        @shipments = @stock_transfer.stock_transfer_shipments.ordered
          .includes(:sent_by, :received_by, :voided_by,
            stock_transfer_shipment_lines: { stock_transfer_line: { ingredient: :ingredient_category } })
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
          transferred_on: Date.current,
          from_location_id: params[:from_location_id],
          to_location_id: params[:to_location_id]
        )
        authorize_inventory!(:create)
        apply_template_if_present
        build_line_items
        load_form_data
      end

      def create
        # Status must be set BEFORE nested attributes are assigned: reject_transfer_line?
        # consults `draft?` as each line comes in, so assigning params first would
        # drop the blank-quantity rows a draft is supposed to keep.
        @stock_transfer = StockTransfer.new
        @stock_transfer.status = "draft" if save_as_draft?
        @stock_transfer.assign_attributes(stock_transfer_params)
        @stock_transfer.requested_by = current_user
        authorize_inventory!(:create)

        if save_transfer_with_lines
          redirect_to admin_inventory_stock_transfer_path(@stock_transfer),
            notice: t(save_as_draft? ? "flash.stock_transfer.draft_saved" : "flash.stock_transfer.requested")
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

        was_draft = @stock_transfer.draft?
        promoting = was_draft && !save_as_draft?

        # Snapshot units before any changes so we can detect what changed.
        unit_snapshot_before = capture_line_units(@stock_transfer)

        @stock_transfer.assign_attributes(stock_transfer_params)

        # Persist the edits while the record is still a draft, so placeholder
        # lines survive, then promote through the same service the show-page
        # button uses. Autosave only validates *changed* children, so flipping
        # the status inline would let an untouched placeholder line slip into a
        # submitted transfer.
        return render_edit_with_errors unless save_transfer_with_lines

        audit_unit_changes(@stock_transfer, unit_snapshot_before)

        if promoting
          begin
            ::Inventory::SubmitStockTransferService.new(@stock_transfer, current_user).call
          rescue ActiveRecord::RecordInvalid
            return render_edit_with_errors
          end
        end

        redirect_to admin_inventory_stock_transfer_path(@stock_transfer),
          notice: t(update_notice_key(was_draft: was_draft, promoting: promoting))
      end

      def submit
        authorize_inventory!(:update)
        ::Inventory::SubmitStockTransferService.new(@stock_transfer, current_user).call
        redirect_to admin_inventory_stock_transfer_path(@stock_transfer),
          notice: t("flash.stock_transfer.requested")
      rescue ActiveRecord::RecordInvalid => e
        redirect_to admin_inventory_stock_transfer_path(@stock_transfer),
          alert: e.record.errors.full_messages.to_sentence
      end

      # Only drafts are destroyable — a submitted transfer is an audit record
      # and gets cancelled instead.
      def destroy
        authorize_inventory!(:update)
        unless @stock_transfer.discardable?
          redirect_to admin_inventory_stock_transfer_path(@stock_transfer),
            alert: t("inventory.stock_transfers.errors.cannot_discard")
          return
        end

        @stock_transfer.destroy!
        redirect_to admin_inventory_stock_transfers_path(status: "draft"),
          notice: t("flash.stock_transfer.draft_discarded")
      end

      def send_transfer
        authorize_inventory!(:update)
        ::Inventory::SendStockTransferService.new(
          @stock_transfer,
          current_user,
          line_quantities: line_quantity_params,
          allow_overage: params[:allow_overage] == "1",
          send_token: params[:send_token]
        ).call
        redirect_to admin_inventory_stock_transfer_path(@stock_transfer),
          notice: t("flash.stock_transfer.sent")
      rescue ActiveRecord::RecordInvalid => e
        redirect_to admin_inventory_stock_transfer_path(@stock_transfer),
          alert: e.record.errors.full_messages.to_sentence
      rescue ActiveRecord::RecordNotUnique
        # The same form was submitted twice — a double click. The first one won,
        # so this is already done rather than an error to show the user.
        redirect_to admin_inventory_stock_transfer_path(@stock_transfer),
          notice: t("flash.stock_transfer.sent")
      end

      def revert_shipment
        authorize_inventory!(:update)
        result = ::Inventory::RevertReceivedStockTransferShipmentService.new(
          @stock_transfer,
          current_user,
          shipment: requested_shipment,
          reason: params[:revert_reason]
        ).call

        redirect_to admin_inventory_stock_transfer_path(@stock_transfer),
          notice: revert_notice(result)
      rescue ActiveRecord::RecordNotFound
        redirect_to admin_inventory_stock_transfer_path(@stock_transfer),
          alert: t("inventory.stock_transfers.errors.cannot_revert_shipment")
      rescue ActiveRecord::RecordInvalid => e
        redirect_to admin_inventory_stock_transfer_path(@stock_transfer),
          alert: e.record.errors.full_messages.to_sentence
      end

      def confirm_receipt
        authorize_inventory!(:update)
        shipment = requested_shipment
        ::Inventory::ConfirmStockTransferService.new(
          @stock_transfer,
          current_user,
          line_quantities: line_quantity_params,
          receipt_notes: params[:receipt_notes],
          shipment: shipment
        ).call
        redirect_to admin_inventory_stock_transfer_path(@stock_transfer),
          notice: t("flash.stock_transfer.received")
      rescue ActiveRecord::RecordNotFound
        redirect_to admin_inventory_stock_transfer_path(@stock_transfer),
          alert: t("inventory.stock_transfers.errors.cannot_confirm")
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

      # Accept the shortfall and finish the transfer. Without this a partially
      # received transfer had no terminal state and stayed in the Open queue forever.
      def close_short
        authorize_inventory!(:update)
        ::Inventory::CloseShortStockTransferService.new(
          @stock_transfer, current_user, reason: params[:closed_short_reason]
        ).call
        redirect_to admin_inventory_stock_transfer_path(@stock_transfer),
          notice: t("flash.stock_transfer.closed_short")
      rescue ::Inventory::CloseShortStockTransferService::Error => e
        redirect_to admin_inventory_stock_transfer_path(@stock_transfer), alert: e.message
      end

      def void_shipment
        authorize_inventory!(:update)
        ::Inventory::VoidInTransitStockTransferShipmentService.new(
          @stock_transfer, current_user, shipment: requested_shipment
        ).call
        redirect_to admin_inventory_stock_transfer_path(@stock_transfer),
          notice: t("flash.stock_transfer.shipment_voided")
      rescue ActiveRecord::RecordNotFound
        redirect_to admin_inventory_stock_transfer_path(@stock_transfer),
          alert: t("inventory.stock_transfers.errors.cannot_void_shipment")
      rescue ActiveRecord::RecordInvalid => e
        redirect_to admin_inventory_stock_transfer_path(@stock_transfer),
          alert: e.record.errors.full_messages.to_sentence
      end

      private

      # Several shipments can be open at once, so receive and void name the one they
      # act on. Scoped through the transfer, and an id that does not resolve is an
      # error — falling back to "whichever is current" would let a wrong or foreign
      # id quietly act on a different shipment.
      # A reversal that could not be fully covered leaves the destination
      # negative, which the user must know about immediately — it is the
      # difference between a clean correction and stock that needs recounting.
      def revert_notice(result)
        return t("flash.stock_transfer.shipment_reverted") unless result.left_destination_short?

        t("flash.stock_transfer.shipment_reverted_short",
          items: result.short_lines.map { |row| row[:line].ingredient.name }.to_sentence)
      end

      def requested_shipment
        return nil if params[:shipment_id].blank?

        @stock_transfer.stock_transfer_shipments.find_by(id: params[:shipment_id]) ||
          raise(ActiveRecord::RecordNotFound)
      end

      def set_stock_transfer
        @stock_transfer = StockTransfer.find(params[:id])
      end

      def stock_transfer_params
        permitted_stock_transfer_params
      end

      def permitted_stock_transfer_params
        params.require(:stock_transfer).permit(
          :from_location_id, :to_location_id, :notes, :transferred_on,
          :stock_transfer_template_id,
          stock_transfer_lines_attributes: %i[
            id ingredient_id quantity_requested quantity_requested_input unit
            order_limit counted_quantity position _destroy
          ]
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

      def save_as_draft?
        params.key?(:save_draft)
      end

      def update_notice_key(was_draft:, promoting:)
        return "flash.stock_transfer.requested" if promoting
        return "flash.stock_transfer.draft_saved" if was_draft

        "flash.stock_transfer.updated"
      end

      def render_edit_with_errors
        build_line_items
        load_form_data
        render :edit, status: :unprocessable_entity
      end

      def build_line_items
        @stock_transfer.stock_transfer_lines.build if @stock_transfer.stock_transfer_lines.empty?
      end

      def apply_template_if_present
        return if params[:template_id].blank?

        template = StockTransferTemplate.active.find_by(id: params[:template_id])
        return if template.blank?

        @applied_template = template
        @stock_transfer.stock_transfer_template = template
        @stock_transfer.from_location_id ||= template.default_from_location_id
        @stock_transfer.to_location_id ||= template.default_to_location_id
        if @stock_transfer.notes.blank? && template.notes.present?
          @stock_transfer.notes = template.notes
        end

        template.stock_transfer_template_lines
          .includes(:ingredient)
          .ordered
          .each_with_index do |line, index|
            @stock_transfer.stock_transfer_lines.build(
              ingredient: line.ingredient,
              unit: line.unit.presence || line.ingredient.unit,
              order_limit: line.default_quantity,
              position: index
            )
          end
      end

      def save_transfer_with_lines
        active_lines = @stock_transfer.stock_transfer_lines.reject(&:marked_for_destruction?)
        # A draft is allowed to be empty — that is the point of saving one.
        if active_lines.empty? && !@stock_transfer.draft?
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

      def with_index_associations
        StockTransfer.includes(:from_location, :to_location, :requested_by, :sent_by, :received_by)
      end

      def apply_location_filter(scope)
        return scope if params[:location_id].blank?

        loc_id = params[:location_id]
        scope.where("stock_transfers.from_location_id = ? OR stock_transfers.to_location_id = ?", loc_id, loc_id)
      end

      def apply_scope(scope)
        scope = filtered_base(scope)
        return scope.where(status: @status) if @status

        case @scope_name
        when "today" then scope.on_date(Date.current)
        when "all"   then scope
        else              scope.in_progress
        end
      end

      # Every narrowing filter in one place, so the tab badges and the list they
      # lead to are always counting the same rows.
      def filtered_base(scope)
        scope = apply_location_filter(scope)
        scope = apply_route_filter(scope)
        scope = apply_date_filter(scope)
        apply_ingredient_filter(scope)
      end

      # Drill-down from the transfer trends report, which analyses one ingredient
      # on one route over one period.
      def apply_route_filter(scope)
        scope = scope.where(from_location_id: params[:from_location_id]) if params[:from_location_id].present?
        scope = scope.where(to_location_id: params[:to_location_id]) if params[:to_location_id].present?
        scope
      end

      def apply_date_filter(scope)
        from = safe_filter_date(:start_date)
        to = safe_filter_date(:end_date)
        return scope if from.nil? && to.nil?

        scope.where(transferred_on: (from || to)..(to || from))
      end

      def apply_ingredient_filter(scope)
        return scope if params[:ingredient_id].blank?

        scope.where(
          id: StockTransferLine.where(ingredient_id: params[:ingredient_id]).select(:stock_transfer_id)
        )
      end

      def safe_filter_date(key)
        params[key].presence&.to_date
      rescue ArgumentError, TypeError, Date::Error
        nil
      end

      # True when the list has been narrowed by a drill-down rather than by the
      # tabs, so the page can say so — an unexplained short list reads as data
      # loss on a work queue.
      def drilled_down?
        params[:ingredient_id].present? || params[:from_location_id].present? ||
          params[:to_location_id].present? || params[:start_date].present? ||
          params[:end_date].present?
      end
      helper_method :drilled_down?

      # One grouped query plus one for today; the rest is derived so the tab
      # badges always match what clicking the tab actually returns.
      def load_tab_counts
        counting_base = filtered_base(StockTransfer.all)
        @status_counts = counting_base.group(:status).count
        @all_count     = @status_counts.values.sum
        @open_count    = StockTransfer::IN_PROGRESS_STATUSES.sum { |st| @status_counts[st].to_i }
        @today_count   = counting_base.on_date(Date.current).count
      end

      # Shown under the open queue so "shipped and received, done" is visible
      # without switching tabs.
      def load_completed_today
        @completed_today = apply_location_filter(with_index_associations)
          .where(status: "completed")
          .on_date(Date.current)
          .order(created_at: :desc)
      end

      def apply_sort(scope)
        dir = @direction == "asc" ? :asc : :desc

        case @sort
        when "transfer_number"
          scope.order(transfer_number: dir)
        when "transferred_on"
          scope.order(transferred_on: dir, created_at: :desc)
        when "status"
          scope.order(status: dir, transferred_on: :desc)
        when "from_location"
          scope.joins(:from_location).order("locations.name #{dir}")
        when "to_location"
          scope.joins(:to_location).order(Arel.sql("(SELECT name FROM locations WHERE id = stock_transfers.to_location_id) #{dir}"))
        when "requested_by"
          scope.joins(:requested_by).order(Arel.sql("(SELECT name FROM users WHERE id = stock_transfers.requested_by_id) #{dir}"))
        else
          if @scope_name == "open"
            # Aging queue: the longest-outstanding transfer needs attention first.
            scope.order(transferred_on: :asc, created_at: :asc)
          else
            # newest created_at first (id desc equivalent for UUIDs with timestamps)
            scope.order(created_at: :desc)
          end
        end
      end

      # Returns {line_id => unit} for all persisted lines on a transfer.
      def capture_line_units(transfer)
        transfer.stock_transfer_lines.select(&:persisted?).to_h { |l| [l.id, l.unit] }
      end

      # Compare current line units against the snapshot taken before the save;
      # write one AuditLogEntry per line whose unit actually changed.
      def audit_unit_changes(transfer, before_snapshot)
        transfer.stock_transfer_lines.each do |line|
          next unless line.persisted?
          old_unit = before_snapshot[line.id]
          next if old_unit.blank? || old_unit == line.unit

          ::AuditLogEntry.record!(
            action: "stock_transfer_line.unit_changed",
            record: line,
            user: current_user,
            changes_snapshot: {
              line_id: line.id,
              ingredient: line.ingredient&.name,
              from_unit: old_unit,
              to_unit: line.unit
            }
          )
        end
      end

      def record_for_policy
        @stock_transfer || super
      end
    end
  end
end
