# frozen_string_literal: true

module OnlineOrders
  # Takes a self-order from the public menu: checks it against the spam guards,
  # prices it on the server (Orders::QuoteService — the browser's prices are never
  # read), and saves it as a pending OnlineOrderRequest for a cashier to accept.
  #
  # No customer is created here; a new phone only becomes a Customer when a
  # cashier accepts its first order. An existing customer is linked so blocks and
  # history apply.
  #
  # staff: a call-center agent sending the order for the customer (channel
  # "call_center"). The branch must take call-center orders (its own switch, not
  # the public-menu hours); the spam guards and the online maximum are skipped
  # because a staff member typed it; and it never expires — EscalateJob nudges the
  # branch instead.
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
    #         payment_method (one the branch offers; blank = cash),
    #         payment_proof_image (an upload; required when that method is prepaid),
    #         items (array of { menu_item_id | combo_id, modifier_ids, quantity, notes }),
    #         website (honeypot — must stay blank), started_at (signed, see .page_stamp)
    def initialize(location:, params:, ip: nil, user_agent: nil, now: Time.current, staff: nil)
      @location = location
      @staff = staff
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
      if staff?
        return fail(:closed) unless @location.taking_call_center_orders?
      else
        return fail(:closed) unless @location.accepting_online_orders?(@now)
        return fail(:spam) if @params[:website].present? || too_fast?
      end

      @phone = Phones::EgyptianMobile.normalize(@params[:phone])
      return fail(:invalid_phone) if @phone.nil?
      return fail(:missing_name) if customer_name.blank?

      customer = FindOrCreateCustomer.lookup(@phone)
      return fail(:blocked) if customer&.blocked?
      unless staff?
        return fail(:too_many_pending) if recent.pending.where(phone: @phone).count >= MAX_PENDING_PER_PHONE
        return fail(:too_many_today) if recent.where(phone: @phone).where(created_at: @now.beginning_of_day..).count >= MAX_PER_PHONE_PER_DAY
        return fail(:too_many_requests) if @ip.present? && recent.where(ip: @ip, created_at: (@now - 1.hour)..).count >= MAX_PER_IP_PER_HOUR
      end

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
      if !staff? && @location.online_max_order_cents.present? && quote.total_cents > @location.online_max_order_cents
        return fail(:too_large, { "max_cents" => @location.online_max_order_cents })
      end

      payment = @location.offered_online_payment_methods.find { |m| m.payment_method == payment_method_param }
      return fail(:bad_payment_method) if payment.nil?

      proof = @params[:payment_proof_image] if payment.requires_proof?
      if payment.requires_proof?
        return fail(:missing_proof) if proof.blank? || proof.is_a?(String)
        return fail(:bad_proof) unless OnlineOrderRequest.acceptable_proof?(proof)
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
        payment_method: payment.payment_method,
        prepaid: payment.requires_proof?,
        payment_proof_image: proof,
        ip: @ip,
        user_agent: @user_agent,
        channel: staff? ? "call_center" : "public",
        created_by: @staff,
        expires_at: (@now + @location.online_accept_timeout_minutes.minutes unless staff?)
      )
      request.record_check!(:created, now: @now)
      if staff?
        OnlineOrders::EscalateJob.set(wait_until: request.created_at + OnlineOrderRequest::ESCALATE_AFTER)
                                 .perform_later(request.id)
      else
        OnlineOrders::ExpireJob.set(wait_until: request.expires_at).perform_later(request.id)
      end
      OnlineOrders::Broadcast.inbox(@location)
      Result.new(request: request)
    end

    private

    def staff? = @staff.present?

    def fail(code, details = nil)
      Result.new(error: code, details: details)
    end

    def recent
      OnlineOrderRequest.where(created_at: (@now - 1.day)..)
    end

    def payment_method_param
      @params[:payment_method].presence || "cash"
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
  end
end
