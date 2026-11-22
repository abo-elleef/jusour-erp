# frozen_string_literal: true

module OnlineOrders
  # Live updates whenever a request arrives, is decided, expires or is cancelled:
  # the registers of its branch (the "Online (n)" badge and the inbox page) and the
  # company's call-center screens (each agent's list of what they sent).
  module Broadcast
    module_function

    def stream_name(location)
      "pos_online_#{location.company_id}_#{location.id}"
    end

    def inbox_stream_name(location)
      "#{stream_name(location)}_inbox"
    end

    def call_center_stream_name(company_id)
      "call_center_#{company_id}"
    end

    # nudge: a call-center request has waited too long — ring again even though
    # the count didn't go up (EscalateJob).
    def inbox(location, nudge: false)
      waiting = OnlineOrderRequest.unscoped_by_company.where(location_id: location.id).waiting
      count = waiting.count
      late = waiting.call_center.where(created_at: ..(Time.current - OnlineOrderRequest::ESCALATE_AFTER)).count
      Turbo::StreamsChannel.broadcast_replace_to(
        stream_name(location),
        target: "online-orders-badge",
        partial: "pos/online_order_requests/badge",
        locals: { count: count, late: late, nudge: (SecureRandom.hex(4) if nudge), location: location, ring: true }
      )
      # The inbox page itself listens on its own stream and reloads in place.
      Turbo::StreamsChannel.broadcast_refresh_to(inbox_stream_name(location))
      Turbo::StreamsChannel.broadcast_refresh_to(call_center_stream_name(location.company_id))
    end
  end
end
