# frozen_string_literal: true

class KitchenController < ApplicationController
  include FeatureGated

  before_action { require_feature!(:kds) }
  before_action :require_kitchen!
  layout "kitchen"

  def index
    authorize :kds, :view?, policy_class: KdsPolicy
    @orders = Order.kitchen_queue.includes(order_items: [:menu_item, :combo, :order_item_modifiers]).order(:created_at)
  end

  def start
    authorize :kds, :start?, policy_class: KdsPolicy
    order = Order.find(params[:id])
    order.start_prep! if order.may_start_prep?
    redirect_to kitchen_path
  end

  def ready
    authorize :kds, :ready?, policy_class: KdsPolicy
    order = Order.find(params[:id])
    order.mark_ready! if order.may_mark_ready?
    redirect_to kitchen_path
  end

  private

  def require_kitchen!
    return if current_user&.can_access_kds?

    flash[:alert] = t("flash.kitchen_access")
    redirect_to root_path
  end
end
