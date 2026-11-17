# frozen_string_literal: true

require "csv"

module Admin
  module Accounting
    # Order notes: every note cashiers typed on POS orders (whole-order notes and
    # per-item kitchen notes), from the same orders the Sales report counts.
    # Reached from the Sales report — each category / item / choice row there
    # links here already filtered — and filterable on its own.
    class OrderNotesController < BaseController
      before_action { require_feature!(:menu) }

      PER_PAGE = 50

      def index
        parse_date_range
        @include_open = params[:include_open] == "1"
        @locations = Location.branches.ordered
        @location = @locations.find_by(id: params[:location_id]) if params[:location_id].present?
        @categories = Category.order(:position, :name)
        @category = params[:category] if params[:category] == ::Accounting::OrderNotesService::COMBOS || @categories.exists?(id: params[:category].presence)
        @kind = params[:kind] if ::Accounting::OrderNotesService::KINDS.include?(params[:kind])
        @query = params[:q].to_s.strip.presence

        base = { include_open: @include_open, location_id: @location&.id, category: @category }
        options = ::Accounting::OrderNotesService.new(@start_date, @end_date, **base)
        @item_options = options.item_options
        @item = params[:item] if @item_options.any? { |_, key| key == params[:item] }

        chooser = ::Accounting::OrderNotesService.new(@start_date, @end_date, **base, item: @item)
        @choice_options = chooser.choice_options
        if @choice_options.include?([params[:modifier_group], params[:modifier_choice]])
          @modifier_group = params[:modifier_group]
          @modifier_choice = params[:modifier_choice]
        end

        @notes = ::Accounting::OrderNotesService.new(
          @start_date, @end_date, **base, item: @item,
          modifier_group: @modifier_group, modifier_choice: @modifier_choice,
          kind: @kind, query: @query
        ).notes

        respond_to do |format|
          format.html { @pagy, @page_notes = pagy(:offset, @notes, limit: PER_PAGE) }
          format.csv { send_data notes_csv, filename: "order-notes-#{@start_date}-#{@end_date}.csv" }
        end
      end

      private

      def notes_csv
        CSV.generate(headers: true) do |csv|
          csv << [t("accounting.order_notes.business_date"), t("accounting.order_notes.time"), t("accounting.order_notes.order"),
                  t("accounting.sales_reports.branch"), t("accounting.order_notes.cashier"), t("accounting.order_notes.kind"),
                  t("accounting.shared.category"), t("accounting.sales_reports.item"), t("accounting.order_notes.choices"),
                  t("accounting.order_notes.quantity"), t("accounting.order_notes.note")]
          @notes.each do |n|
            order = n[:order]
            csv << [order.business_date, order.ticket_time&.strftime("%H:%M"), order.display_number,
                    order.location&.name, order.user&.name, t("accounting.order_notes.kinds.#{n[:kind]}"),
                    n[:category], n[:item_name], n[:modifiers].join(", "), n[:quantity], n[:text]]
          end
        end
      end
    end
  end
end
