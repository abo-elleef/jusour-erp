# frozen_string_literal: true

class PosController < ApplicationController
  layout "pos"

  before_action :require_cashier!
  before_action :set_order, except: %i[new_order submit]
  before_action :no_cache, only: :index

  def index
    authorize @order, :show?
    @order.recalculate_totals!
    @categories = Category.active.ordered
    @menu_items = MenuItem.available
      .includes(:modifier_groups, :category, image_attachment: :blob)
      .order(:position, :name)
    @combos = Combo.active.order(:name)
    @open_orders = Order.open_drafts.where(user: current_user).order(created_at: :desc).limit(10)
  end

  def new_order
    authorize Order, :create?
    session.delete(:current_order_id)
    redirect_to pos_path, status: :see_other
  end

  def apply_coupon
    authorize @order, :update?
    Discounts::ApplyDiscountService.call(order: @order, code: params[:code])
    redirect_to pos_path, notice: "Coupon applied."
  rescue Discounts::ApplyDiscountService::InvalidDiscount => e
    redirect_to pos_path, alert: e.message
  end

  def manager_discount
    authorize @order, :update?
    unless current_user.admin_access? && params[:pin] == ENV.fetch("MANAGER_PIN", "1234")
      return redirect_to pos_path, alert: "Invalid manager PIN"
    end

    Discounts::ApplyDiscountService.call(
      order: @order,
      manager_override_cents: params[:amount_cents].to_i,
      description: "Manager Override"
    )
    redirect_to pos_path, notice: "Discount applied."
  end

  def redeem_points
    authorize @order, :update?
    Loyalty::RedeemPointsService.call(order: @order)
    redirect_to pos_path, notice: "Points redeemed."
  rescue Loyalty::RedeemPointsService::InsufficientPoints => e
    redirect_to pos_path, alert: e.message
  end

  def submit
    order = current_draft_order
    return redirect_to pos_path, alert: "No active order to send.", status: :see_other unless order

    authorize order, :submit?
    Orders::SubmitService.call(order)
    session.delete(:current_order_id)
    redirect_to pos_path, notice: "Sent to kitchen.", status: :see_other
  rescue Orders::SubmitService::InvalidFulfillment => e
    redirect_to pos_path, alert: e.message, status: :see_other
  end

  def update_fulfillment
    authorize @order, :update?
    if @order.update(fulfillment_params)
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to pos_path }
      end
    else
      respond_to do |format|
        format.turbo_stream { render :update_fulfillment, status: :unprocessable_entity }
        format.html { redirect_to pos_path, alert: @order.errors.full_messages.to_sentence }
      end
    end
  end

  def attach_customer
    authorize @order, :update?
    customer = Customer.find_by(id: params[:customer_id]) ||
               Customer.find_by(phone: params[:phone]) ||
               Customer.find_by(email: params[:email])
    if customer
      @order.update!(customer: customer)
    elsif params[:name].present?
      customer = Customer.create!(customer_params)
      @order.update!(customer: customer)
    end
    redirect_to pos_path
  end

  def split
    authorize @order, :split?
    new_order = Orders::CreateService.call(
      user: current_user,
      customer: @order.customer,
      order_type: @order.order_type,
      table_number: @order.table_number,
      delivery_address: @order.delivery_address
    )
    item_ids = params[:order_item_ids] || []
    @order.order_items.where(id: item_ids).update_all(order_id: new_order.id)
    @order.recalculate_totals!
    new_order.recalculate_totals!
    session[:current_order_id] = new_order.id
    redirect_to pos_path, notice: "Order split."
  end

  def merge
    authorize @order, :merge?
    other = Order.open_drafts.find(params[:other_order_id])
    other.order_items.update_all(order_id: @order.id)
    other.destroy
    @order.recalculate_totals!
    redirect_to pos_path, notice: "Orders merged."
  end

  private

  def require_cashier!
    return if current_user&.cashier? || current_user&.admin_access?

    flash[:alert] = "POS access only for cashiers."
    redirect_to root_path
  end

  def set_order
    @order = current_draft_order || assign_new_draft_order!
    @order.recalculate_totals!
  end

  def current_draft_order
    return unless session[:current_order_id]

    Order.find_by(id: session[:current_order_id], status: "draft")
  end

  def assign_new_draft_order!
    order = Orders::CreateService.call(user: current_user)
    session[:current_order_id] = order.id
    order
  end

  def no_cache
    response.headers["Cache-Control"] = "no-store, no-cache, must-revalidate"
    response.headers["Pragma"] = "no-cache"
  end

  def customer_params
    params.permit(:name, :email, :phone)
  end

  def fulfillment_params
    params.permit(:order_type, :table_number, :delivery_address)
  end
end
