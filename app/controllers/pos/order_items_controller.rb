# frozen_string_literal: true

module Pos
  class OrderItemsController < ApplicationController
    include PosLocationScoped
    include OpenDrawerGate

    before_action :require_pos_access!
    # Before set_order, which would otherwise create the order this is meant to stop.
    # Taking a line off (destroy) is never blocked.
    before_action(only: %i[create update]) { require_open_drawer_to_order!(location: current_pos_location) }
    before_action :set_order

    def create
      authorize @order, :update?
      @order.with_lock do
        first_item = @order.order_items.none?
        # The line this add landed on (new, or an existing one whose quantity went
        # up): the basket scrolls to it and highlights it, since lines are sorted by
        # category and name and the new one is not always last.
        @added_item = params[:combo_id] ? add_combo : add_menu_item
        # An empty cart doesn't hold its table, so another register may have taken it
        # since the cashier picked it. The first item is where that shows up. Once the
        # order has items it already holds the table, so later adds are never blocked.
        if first_item && (other = @order.table_conflict)
          raise TableBusy, t("order.errors.table_busy", table: @order.table_number, number: other.display_reference)
        end
        @order.recalculate_totals!
      end
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to pos_path }
      end
    rescue ItemUnavailableAtLocation
      redirect_to pos_path, alert: t("flash.pos.item_unavailable_at_location")
    rescue TableBusy => e
      # The add buttons post from inside the register, where a redirect is lost.
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.append("toast-container", partial: "shared/toast",
                                                                        locals: { message: e.message, type: :alert }),
                 status: :unprocessable_entity
        end
        format.any { redirect_to pos_path, alert: e.message, status: :see_other }
      end
    end

    def update
      authorize @order, :update?
      @order.with_lock do
        item = @order.order_items.find(params[:id])
        if params[:quantity_delta]
          new_quantity = item.quantity + params[:quantity_delta].to_i
          # Minus on the last unit removes the line, as cashiers expect.
          new_quantity <= 0 ? item.destroy! : item.update!(quantity: new_quantity)
        elsif params[:order_item].respond_to?(:keys) && params[:order_item].keys == ["quantity"]
          # A typed count. Zero (or less) removes the line, like minus on the last unit;
          # junk text leaves the line as it was and the re-rendered cart shows the old count.
          typed = params[:order_item][:quantity].to_s.strip
          if typed.match?(/\A-?\d+\z/)
            typed.to_i <= 0 ? item.destroy! : item.update!(quantity: typed.to_i)
          end
        else
          item.update!(order_item_params)
        end
        Promos::SyncOrderItemDiscount.call(order_item: item) if item.persisted? && item.menu_item_id.present?
        @order.recalculate_totals!
      end
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to pos_path }
      end
    end

    def destroy
      authorize @order, :update?
      @order.with_lock do
        @order.order_items.find(params[:id]).destroy
        @order.recalculate_totals!
      end
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to pos_path }
      end
    end

    def modifier_form
      @menu_item = MenuItem.includes(:location_menu_items).find(params[:menu_item_id])
      unless @menu_item.available_at_location?(@order.location)
        return redirect_to pos_path, alert: t("flash.pos.item_unavailable_at_location")
      end

      render partial: "pos/modifier_modal", locals: { menu_item: @menu_item, order: @order }
    end

    private

    class ItemUnavailableAtLocation < StandardError; end
    class TableBusy < StandardError; end

    def require_pos_access!
      return if current_user&.can_access_pos?

      flash[:alert] = t("flash.pos_access")
      redirect_to root_path
    end

    def set_order
      # Only the cart, or a placed order a manager unlocked, takes item changes.
      @order = Order.cart_editable.find_by(id: session[:current_order_id])
      # Only adding an item saves a new cart. Opening the add popup (modifier_form)
      # used to save one too, so every popup the cashier cancelled left an empty
      # takeaway draft behind; the popup only needs the branch.
      @order ||= case action_name
                 when "create" then materialize_pending_order!
                 when "modifier_form" then Order.new(location: current_pos_location, user: current_user)
                 end
      return redirect_to(pos_path, status: :see_other) unless @order
      return if current_pos_location.blank? || @order.new_record?

      attrs = {}
      attrs[:location] = current_pos_location if @order.location_id.blank?
      if current_pos_workstation.present? && @order.workstation_id != current_pos_workstation.id
        attrs[:workstation] = current_pos_workstation
      end
      @order.update!(attrs) if attrs.any?
    end

    # Creates the DB record from pending session params (set by PosController when
    # no existing draft was found). Clears pending params once persisted.
    def materialize_pending_order!
      pending = session[:pending_order_params] || {}
      order = Orders::CreateService.call(
        user:             current_user,
        location:         current_pos_location,
        workstation:      current_pos_workstation,
        order_type:       pending["order_type"].presence || "pickup",
        table_number:     pending["table_number"],
        delivery_address: pending["delivery_address"]
      )
      session.delete(:pending_order_params)
      session[:current_order_id] = order.id
      order
    end

    # Prices come from the database only; see Orders::ResolveLine.
    def add_combo
      add_line(combo_id: params[:combo_id])
    end

    def add_menu_item
      add_line(
        menu_item_id: params[:menu_item_id],
        modifier_ids: Array(params[:modifier_ids]) + Array(params[:modifier_group_selections]&.values),
        quantity: params[:quantity],
        notes: params[:notes]
      )
    end

    def add_line(**attrs)
      line = Orders::ResolveLine.call(location: @order.location, **attrs)
      Orders::AddLineService.call(order: @order, line: line)
    rescue Orders::ResolveLine::Invalid
      raise ItemUnavailableAtLocation
    end

    def order_item_params
      params.require(:order_item).permit(:quantity, :notes)
    end
  end
end
