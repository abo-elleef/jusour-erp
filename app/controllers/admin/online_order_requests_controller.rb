# frozen_string_literal: true

module Admin
  # Every self-order across branches: accepted, rejected, expired, waiting. The
  # place to see how online ordering is going and to spot spam patterns (the same
  # phone or connection over and over, many rejections).
  class OnlineOrderRequestsController < BaseController
    before_action { require_feature!(:menu) }

    INDEX_SORTS = {
      "created_at" => "online_order_requests.created_at",
      "customer" => "online_order_requests.customer_name",
      "status" => "online_order_requests.status",
      "total" => "online_order_requests.total_cents"
    }.freeze

    def index
      authorize OnlineOrderRequest

      @q = OnlineOrderRequest.ransack(params[:q])
      scope = @q.result.includes(:location, :order, :decided_by, :customer, :created_by)
      @filter_date = params[:date].presence
      if @filter_date && (day = Date.parse(@filter_date) rescue nil)
        scope = scope.where(created_at: day.in_time_zone.all_day)
      end

      @summary = scope.unscope(:includes).group(:status).count
      @sort = INDEX_SORTS.key?(params[:sort].to_s) ? params[:sort].to_s : "created_at"
      @direction = %w[asc desc].include?(params[:dir].to_s) ? params[:dir].to_s : "desc"
      scope = scope.order(Arel.sql("#{INDEX_SORTS.fetch(@sort)} #{@direction}"))
      @pagy, @requests = pagy(:offset, scope, limit: 50)
      @locations = Location.where(location_type: "branch").ordered
    end

    # The whole story of one request: what the customer sent, what the system
    # knew about the phone when it came in and when it was decided, and who
    # accepted or rejected it and why.
    def show
      @request = OnlineOrderRequest.includes(:location, :order, :decided_by, :delivery_area).find_by!(token: params[:id])
      authorize @request
      @created_check = @request.check_snapshot(:created)
      @decided_check = @request.check_snapshot(:decided)
      @live_check = OnlineOrders::CustomerCheck.new(@request)
      @customer = @live_check.customer
      @same_phone = OnlineOrderRequest.where(phone: @request.phone).where.not(id: @request.id)
                                      .includes(:location, :decided_by, :order).recent_first.limit(10)
    end
  end
end
