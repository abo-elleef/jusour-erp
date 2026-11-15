# frozen_string_literal: true

module OnlineOrders
  # Takes a self-order from the public menu: checks it against the spam guards,
  # prices it on the server (Orders::QuoteService — the browser's prices are never
  # read), and saves it as a pending OnlineOrderRequest for a cashier to accept.
  #
  # No customer is created here; a new phone only becomes a Customer when a
  # cashier accepts its first order. An existing customer is linked so blocks and
  # history apply.
  class SubmitService
    MAX_PENDING_PER_PHONE = 2
    MAX_PER_PHONE_PER_DAY = 5
    MAX_PER_IP_PER_HOUR = 8
    MIN_SECONDS_ON_PAGE = 3

    Result = Struct.new(:request, :error, :details, keyword_init: true) do
      def ok? = error.nil?
    end

    def self.call(...)
      new(...).call
    end

    # params: customer_name, phone, fulfillment, delivery_area_id, address, note,
    #         items (array of { menu_item_id | combo_id, modifier_ids, quantity, notes }),
    #         website (honeypot — must stay blank), started_at (signed, see .page_stamp)
    def initialize(location:, params:, ip: nil, user_agent: nil, now: Time.current)
      @location = location
      @params = params.to_h.with_indifferent_access
      @ip = ip
      @user_agent = user_agent.to_s.first(255)
      @now = now
    end

    # Signed render time, so a bot can't fake "the customer spent a while on the page".
    def self.page_stamp(now = Time.current)
      verifier.generate(now.to_i, purpose: :online_order)
    end

    def self.verifier
      Rails.application.message_verifier("online_orders")
    end

    def call
      return fail(:closed) unless @location.accepting_online_orders?(@now)
      return fail(:spam) if @params[:website].present? || too_fast?

      @phone = Phones::EgyptianMobile.normalize(@params[:phone])
      return fail(:invalid_phone) if @phone.nil?
      return fail(:missing_name) if customer_name.blank?

      customer = existing_customer
      return fail(:blocked) if customer&.blocked?
      return fail(:too_many_pending) if recent.pending.where(phone: @phone).count >= MAX_PENDING_PER_PHONE
      return fail(:too_many_today) if recent.where(phone: @phone).where(created_at: @now.beginning_of_day..).count >= MAX_PER_PHONE_PER_DAY
      return fail(:too_many_requests) if @ip.present? && recent.where(ip: @ip, created_at: (@now - 1.hour)..).count >= MAX_PER_IP_PER_HOUR

      fulfillment = @params[:fulfillment].to_s
      return fail(:bad_fulfillment) unless OnlineOrderRequest::FULFILLMENTS.include?(fulfillment)

      area = nil
      if fulfillment == "delivery"
        area = @location.delivery_areas.active.find_by(id: @params[:delivery_area_id])
        return fail(:missing_area) if area.nil?
        return fail(:missing_address) if @params[:address].to_s.strip.blank?
      end

      quote = Orders::QuoteService.call(location: @location, items: items, delivery_fee_cents: area&.fee_cents.to_i)
      return fail(:empty_cart) if quote.lines.empty? && quote.errors.empty?
      return fail(:bad_items, quote.errors) unless quote.ok?
      if @location.online_max_order_cents.present? && quote.total_cents > @location.online_max_order_cents
        return fail(:too_large, { "max_cents" => @location.online_max_order_cents })
      end

      request = OnlineOrderRequest.create!(
        location: @location,
        customer: customer,
        delivery_area: area,
        fulfillment: fulfillment,
        customer_name: customer_name,
        phone: @phone,
        address: fulfillment == "delivery" ? @params[:address].to_s.strip.first(500) : nil,
        note: @params[:note].to_s.strip.first(500).presence,
        cart: items,
        quote: quote.snapshot,
        total_cents: quote.total_cents,
        delivery_fee_cents: quote.delivery_fee_cents,
        ip: @ip,
        user_agent: @user_agent,
        expires_at: @now + @location.online_accept_timeout_minutes.minutes
      )
      OnlineOrders::ExpireJob.set(wait_until: request.expires_at).perform_later(request.id)
      OnlineOrders::Broadcast.inbox(@location)
      Result.new(request: request)
    end

    private

    def fail(code, details = nil)
      Result.new(error: code, details: details)
    end

    def recent
      OnlineOrderRequest.where(created_at: (@now - 1.day)..)
    end

    def customer_name
      @params[:customer_name].to_s.strip.first(80)
    end

    def items
      @items ||= Array(@params[:items]).first(Orders::QuoteService::MAX_LINES).map do |raw|
        raw = raw.respond_to?(:permit) ? raw.permit(:menu_item_id, :combo_id, :quantity, :notes, modifier_ids: []).to_h : raw.to_h
        raw = raw.stringify_keys
        {
          "menu_item_id" => raw["menu_item_id"].presence, "combo_id" => raw["combo_id"].presence,
          "modifier_ids" => Array(raw["modifier_ids"]).map(&:to_s), "quantity" => raw["quantity"].to_i,
          "notes" => raw["notes"].to_s.strip.first(200).presence
        }.compact
      end
    end

    def too_fast?
      started = self.class.verifier.verified(@params[:started_at].to_s, purpose: :online_order)
      started.nil? || (@now.to_i - started.to_i) < MIN_SECONDS_ON_PAGE
    end

    def existing_customer
      variants = Phones::EgyptianMobile.variants(@phone)
      Customer.where(phone: variants).or(Customer.where(phone_secondary: variants)).first
    end
  end
end
