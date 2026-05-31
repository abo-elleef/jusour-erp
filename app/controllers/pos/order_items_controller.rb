# frozen_string_literal: true

module Pos
  class OrderItemsController < ApplicationController
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
      @menu_item = MenuItem.find(params[:menu_item_id])
      render partial: "pos/modifier_modal", locals: { menu_item: @menu_item, order: @order }
    end

    private

    def require_pos_access!
      return if current_user&.cashier? || current_user&.admin_access?

      flash[:alert] = t("flash.pos_access")
      redirect_to root_path
    end

    def set_order
      @order = Order.find_by(id: session[:current_order_id], status: "draft")
      @order ||= begin
        order = Orders::CreateService.call(user: current_user)
        session[:current_order_id] = order.id
        order
      end
    end

    def add_combo
      combo = Combo.find(params[:combo_id])
      @order.order_items.create!(
        combo: combo,
        quantity: 1,
        unit_price_cents: combo.price_cents
      )
    end

    def add_menu_item
      menu_item = MenuItem.find(params[:menu_item_id])
      modifier_ids = Array(params[:modifier_ids])
      unit_price = menu_item.base_price_cents
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
