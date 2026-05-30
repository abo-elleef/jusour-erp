# frozen_string_literal: true

class KitchenController < ApplicationController
  before_action :require_kitchen!
  layout "kitchen"

  def index
    @orders = Order.kitchen_queue.includes(order_items: [:menu_item, :combo, :order_item_modifiers]).order(:created_at)
  end

  def start
    order = Order.find(params[:id])
    order.start_prep! if order.may_start_prep?
    redirect_to kitchen_path
  end

  def ready
    order = Order.find(params[:id])
    order.mark_ready! if order.may_mark_ready?
    redirect_to kitchen_path
  end

  private

  def require_kitchen!
    return if current_user&.kitchen? || current_user&.admin_access?

    flash[:alert] = "Kitchen display access only."
    redirect_to root_path
  end
end
