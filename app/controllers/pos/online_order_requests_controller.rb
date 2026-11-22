# frozen_string_literal: true

module Pos
  # The register's inbox of customer self-orders for its branch: accept (it becomes
  # this cashier's order and is placed) or reject with a reason, optionally blocking
  # the phone. Any POS user can do this; see OnlineOrders::AcceptService.
  class OnlineOrderRequestsController < ApplicationController
    include PosLocationScoped
    include OpenDrawerGate

    layout "pos"

    before_action :require_pos_access!
    before_action :require_location!
    before_action :set_request, only: %i[show accept reject]
    # Accepting creates an order in this cashier's shift, so it needs their drawer.
    before_action(only: :accept) { require_open_drawer_to_order!(location: @pos_location) }

    def index
      scope = OnlineOrderRequest.where(location: @pos_location).includes(:customer, :delivery_area, :order, :decided_by, :created_by)
      @pending = scope.waiting.order(:created_at)
      @checks = @pending.to_h { |req| [req.id, OnlineOrders::CustomerCheck.new(req)] }
      @recent = scope.where.not(status: "pending").where(decided_at: 12.hours.ago..).order(decided_at: :desc).limit(20)
    end

    # Waiting: the live check. Decided: the check as the cashier saw it then
    # (live for requests from before checks were saved).
    def show
      @live_check = OnlineOrders::CustomerCheck.new(@request)
      @check = (@request.check_snapshot(:decided) unless @request.pending?) || @live_check
      @customer = @live_check.customer
    end

    def accept
      result = OnlineOrders::AcceptService.call(request: @request, user: current_user, workstation: @pos_workstation,
                                                confirm_price_change: params[:confirm_price_change].present?)
      if result.ok?
        redirect_to pos_online_order_requests_path,
                    notice: t("pos.online_orders.accepted", number: result.order.order_number)
      elsif result.error == :price_changed
        redirect_to pos_online_order_request_path(@request, new_total: result.new_total_cents)
      else
        redirect_to pos_online_order_requests_path, alert: t("pos.online_orders.errors.#{result.error}")
      end
    rescue Orders::SubmitService::InvalidFulfillment => e
      redirect_to pos_online_order_request_path(@request), alert: e.message
    end

    def reject
      if OnlineOrders::RejectService.call(request: @request, user: current_user, reason: params[:reason],
                                          block: params[:block] == "1", note: params[:note])
        redirect_to pos_online_order_requests_path, notice: t("pos.online_orders.rejected")
      else
        redirect_to pos_online_order_requests_path, alert: t("pos.online_orders.errors.not_pending")
      end
    end

    # Busy rush or closing early: stop (or resume) taking self-orders at this branch.
    def toggle
      @pos_location.update!(online_ordering_enabled: !@pos_location.online_ordering_enabled?)
      AuditLogEntry.record!(action: "location.online_ordering_toggle", record: @pos_location, user: current_user,
                            changes_snapshot: { "online_ordering_enabled" => @pos_location.online_ordering_enabled? })
      redirect_to pos_online_order_requests_path,
                  notice: t(@pos_location.online_ordering_enabled? ? "pos.online_orders.resumed" : "pos.online_orders.paused")
    end

    private

    def require_pos_access!
      return if current_user&.can_access_pos?

      flash[:alert] = t("flash.pos_access")
      redirect_to root_path
    end

    def require_location!
      redirect_to pos_path, alert: t("pos.location.select") if @pos_location.nil?
    end

    def set_request
      @request = OnlineOrderRequest.where(location: @pos_location).find_by!(token: params[:id])
    end
  end
end
