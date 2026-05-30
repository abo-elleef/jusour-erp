# frozen_string_literal: true

module Receipts
  class SendReceiptService
    def self.call(order:, method:, recipient:)
      new(order: order, method: method, recipient: recipient).call
    end

    def initialize(order:, method:, recipient:)
      @order = order
      @method = method
      @recipient = recipient
    end

    def call
      case @method
      when "email"
        send_email
      when "sms"
        send_sms
      end
      @order.update!(receipt_sent_via: @method)
    rescue StandardError => e
      log_failure(e.message)
    end

    private

    def send_email
      ReceiptMailer.order_receipt(@order, @recipient).deliver_later
      log_success("email")
    end

    def send_sms
      client = Twilio::REST::Client.new(
        ENV.fetch("TWILIO_ACCOUNT_SID"),
        ENV.fetch("TWILIO_AUTH_TOKEN")
      )
      url = Rails.application.routes.url_helpers.receipt_url(
        token: @order.receipt_token,
        host: ENV.fetch("APP_HOST", "localhost:3000"),
        protocol: Rails.env.production? ? "https" : "http"
      )
      body = "Thanks! #{@order.order_number} total: $#{@order.total_cents / 100.0}. " \
             "Receipt: #{url}"
      client.messages.create(
        from: ENV.fetch("TWILIO_FROM_NUMBER"),
        to: @recipient,
        body: body
      )
      log_success("sms")
    end

    def log_success(method)
      @order.receipt_logs.create!(
        delivery_method: method,
        recipient: @recipient,
        status: "sent",
        sent_at: Time.current
      )
    end

    def log_failure(message)
      @order.receipt_logs.create!(
        delivery_method: @method,
        recipient: @recipient,
        status: "failed",
        sent_at: Time.current
      )
      Rails.logger.error("Receipt failed: #{message}")
    end
  end
end
