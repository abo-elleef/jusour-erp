# frozen_string_literal: true

module OnlineOrders
  # Live updates to the registers of a branch: the "Online (n)" badge, refreshed
  # whenever a request arrives, is decided, or expires.
  module Broadcast
    module_function

    def stream_name(location)
      "pos_online_#{location.company_id}_#{location.id}"
    end

    def inbox_stream_name(location)
      "#{stream_name(location)}_inbox"
    end

    def inbox(location)
      count = OnlineOrderRequest.unscoped_by_company.where(location_id: location.id).pending
                                .where("expires_at > ?", Time.current).count
      Turbo::StreamsChannel.broadcast_replace_to(
        stream_name(location),
        target: "online-orders-badge",
        partial: "pos/online_order_requests/badge",
        locals: { count: count, location: location, ring: true }
      )
      # The inbox page itself listens on its own stream and reloads in place.
      Turbo::StreamsChannel.broadcast_refresh_to(inbox_stream_name(location))
    end
  end
end
