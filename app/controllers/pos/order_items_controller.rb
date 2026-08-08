# frozen_string_literal: true

module Pos
  class OrderItemsController < ApplicationController
    include PosLocationScoped

    before_action :require_pos_access!
    before_action :set_order

    def create
      authorize @order, :update?
      @order.with_lock do
        if params[:combo_id]
          add_combo
        else
          add_menu_item
        end
        @order.recalculate_totals!
      end
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to pos_path }
      end
    rescue ItemUnavailableAtLocation
      redirect_to pos_path, alert: t("flash.pos.item_unavailable_at_location")
    end

    def update
      authorize @order, :update?
      @order.with_lock do
        item = @order.order_items.find(params[:id])
        if params[:quantity_delta]
          item.update!(quantity: [item.quantity + params[:quantity_delta].to_i, 1].max)
        else
          item.update!(order_item_params)
        end
        Promos::SyncOrderItemDiscount.call(order_item: item) if item.menu_item_id.present?
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

    def require_pos_access!
      return if current_user&.can_access_pos?

      flash[:alert] = t("flash.pos_access")
      redirect_to root_path
    end

    def set_order
      @order = Order.find_by(id: session[:current_order_id], status: "draft")
      @order ||= materialize_pending_order!
      return if current_pos_location.blank?

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

    def add_combo
      combo = Combo.find(params[:combo_id])
      unless Combo.available_at_location(@order.location).exists?(combo.id)
        raise ItemUnavailableAtLocation
      end

      @order.order_items.create!(
        combo: combo,
        quantity: 1,
        unit_price_cents: combo.price_cents
      )
    end

    def add_menu_item
      menu_item = MenuItem.includes(:location_menu_items).find(params[:menu_item_id])
      unless menu_item.available_at_location?(@order.location)
        raise ItemUnavailableAtLocation
      end

      modifier_ids = Array(params[:modifier_ids]) + Array(params[:modifier_group_selections]&.values)
      unit_price = menu_item.price_cents_at(@order.location)
      item = @order.order_items.create!(
        menu_item: menu_item,
        quantity: params[:quantity].to_i.positive? ? params[:quantity].to_i : 1,
        unit_price_cents: unit_price,
        notes: params[:notes]
      )
      Modifier.where(id: modifier_ids).find_each do |mod|
        item.order_item_modifiers.create!(
          modifier: mod,
          name: mod.name,
          price_adjustment_cents: mod.price_adjustment_cents
        )
      end
      Promos::SyncOrderItemDiscount.call(order_item: item)
    end

    def order_item_params
      params.require(:order_item).permit(:quantity, :notes)
    end
  end
end
