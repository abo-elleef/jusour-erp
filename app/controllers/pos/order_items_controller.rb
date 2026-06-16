# frozen_string_literal: true

module Pos
  class OrderItemsController < ApplicationController
    include PosLocationScoped

    before_action :require_pos_access!
    before_action :set_order

    def create
      authorize @order, :update?
      if params[:combo_id]
        add_combo
      else
        add_menu_item
      end
      @order.reload
      @order.recalculate_totals!
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to pos_path }
      end
    rescue ItemUnavailableAtLocation
      redirect_to pos_path, alert: t("flash.pos.item_unavailable_at_location")
    end

    def update
      item = @order.order_items.find(params[:id])
      authorize @order, :update?
      if params[:quantity_delta]
        item.update!(quantity: [item.quantity + params[:quantity_delta].to_i, 1].max)
      else
        item.update!(order_item_params)
      end
      @order.reload
      @order.recalculate_totals!
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to pos_path }
      end
    end

    def destroy
      authorize @order, :update?
      @order.order_items.find(params[:id]).destroy
      @order.reload
      @order.recalculate_totals!
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
      @order ||= begin
        order = Orders::CreateService.call(user: current_user, location: current_pos_location)
        session[:current_order_id] = order.id
        order
      end
      return if @order.location_id.present? || current_pos_location.blank?

      @order.update!(location: current_pos_location)
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
    end

    def order_item_params
      params.require(:order_item).permit(:quantity, :notes)
    end
  end
end
