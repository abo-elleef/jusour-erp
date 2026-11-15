# frozen_string_literal: true

module OnlineOrders
  # A request nobody accepted in time stops waiting, so the customer is told to
  # call instead of staring at "waiting" forever.
  class ExpireJob < ApplicationJob
    queue_as :default

    def perform(request_id)
      request = OnlineOrderRequest.unscoped_by_company.find_by(id: request_id)
      return if request.nil?

      expired = request.with_lock do
        next false unless request.overdue?

        request.update!(status: "expired", decided_at: Time.current)
      end
      Current.set(company: request.company) { Broadcast.inbox(request.location) } if expired
    end
  end
end
