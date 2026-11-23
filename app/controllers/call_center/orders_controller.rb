# frozen_string_literal: true

module CallCenter
  # The call-center screen: staff away from the branches (phone, WhatsApp) build
  # an order on a branch's menu and send it there as a request. A cashier at the
  # branch accepts it (Pos::OnlineOrderRequestsController), so the order is theirs,
  # in their drawer, and prints on the branch's printers. No drawer or register
  # here. The agent's list shows what happened to each request, live.
  class OrdersController < ApplicationController
    include OnlineOrderParams

    layout "call_center"

    before_action :require_call_center!
    before_action :set_location, only: %i[new quote create]

    def index
      @locations = call_center_locations
      @requests = OnlineOrderRequest.call_center.where(created_by: current_user, created_at: Time.current.beginning_of_day..)
                                    .includes(:location, :order, :decided_by).recent_first
      @sent = @requests.find { |req| req.token == params[:sent] } if params[:sent].present?
    end

    def new
      menu = Menus::ForLocation.call(location: @location, channel: :public)
      @categories = menu.categories
      @menu_items = menu.menu_items
      @combos = menu.combos
      @promos_by_item_id = menu.promos_by_item_id
      # Same row as the online menu, since agents order from that menu.
      @top_seller_items = Menus::TopSellerRow.call(location: @location, channel: :public, menu_items: @menu_items)
      @delivery_areas = @location.delivery_areas.active.ordered
      @payment_methods = @location.offered_online_payment_methods
    end

    def quote
      render_quote(@location)
    end

    def create
      result = OnlineOrders::SubmitService.call(location: @location, params: order_params, staff: current_user,
                                                ip: request.remote_ip, user_agent: request.user_agent)
      if result.ok?
        render json: { url: call_center_path(sent: result.request.token) }, status: :created
      else
        render json: { error: result.error, message: online_order_error_message(result) }, status: :unprocessable_content
      end
    end

    def cancel
      req = OnlineOrderRequest.call_center.find_by!(token: params[:token], created_by: current_user)
      if OnlineOrders::CancelService.call(request: req, user: current_user)
        redirect_to call_center_path, notice: t("call_center.cancelled")
      else
        redirect_to call_center_path, alert: t("pos.online_orders.errors.not_pending")
      end
    end

    private

    def require_call_center!
      return if current_user&.can?("orders:take_remote")

      flash[:alert] = t("call_center.no_access")
      redirect_to root_path
    end

    def call_center_locations
      Location.where(id: current_user.accessible_location_ids, call_center_enabled: true, active: true)
              .select(&:branch?).sort_by(&:name)
    end

    def set_location
      @location = call_center_locations.find { |loc| loc.id == params[:location_id] }
      return if @location

      respond_to do |format|
        format.json { render json: { error: :closed, message: t("public.online_order.errors.closed") }, status: :unprocessable_content }
        format.any { redirect_to call_center_path, alert: t("call_center.branch_unavailable") }
      end
    end
  end
end
