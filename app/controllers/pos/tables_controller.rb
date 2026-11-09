# frozen_string_literal: true

module Pos
  # The floor plan for branches that seat customers: which tables hold an open
  # order, and a way to pick one back up. Only exists where Location#table_service
  # is on; everywhere else the register stays pay-first.
  class TablesController < ApplicationController
    include PosLocationScoped
    include OpenDrawerGate

    layout "pos"

    before_action :require_pos_access!
    before_action :require_table_service!

    def index
      authorize Order, :index_for_payment?
      @table_count = @pos_location.table_count
      @busy_tables = Order.busy_tables(@pos_location)
    end

    # Free table: start its order. Busy table: pick up whatever is open on it.
    def open
      authorize Order, :create?
      number = params[:number].to_s
      holder = Order.busy_tables(@pos_location)[number]

      if holder
        return redirect_to pos_order_path(holder, from: "tables") unless holder.draft?

        authorize holder, :resume_table?
        session[:current_order_id] = holder.id
        return redirect_to pos_path, notice: t("flash.pos.order_resumed")
      end

      # Picking up a table already open is allowed; starting one places an order.
      require_open_drawer_to_order!(location: @pos_location)
      return if performed?

      order = Orders::CreateService.call(
        user: current_user, location: @pos_location, workstation: @pos_workstation,
        order_type: "table", table_number: number
      )
      session[:current_order_id] = order.id
      redirect_to pos_path
    rescue ActiveRecord::RecordInvalid => e
      redirect_to pos_tables_path, alert: e.record.errors.full_messages.to_sentence
    end

    private

    def require_pos_access!
      return if current_user&.can_access_pos?

      flash[:alert] = t("flash.pos_access")
      redirect_to root_path
    end

    def require_table_service!
      return if @pos_location&.table_service?

      redirect_to pos_path, alert: t("flash.pos.tables.not_enabled")
    end
  end
end
