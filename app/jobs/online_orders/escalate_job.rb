# frozen_string_literal: true

module OnlineOrders
  # A call-center request never expires, so a branch that missed it would leave it
  # waiting forever. Every ESCALATE_AFTER while it waits, ring the branch's
  # registers again (the badge turns "late" and beeps) and refresh the agent's list,
  # which then tells them to phone the branch. Stops once it is decided, or after
  # MAX_ROUNDS (an hour) — by then a human has had to step in.
  class EscalateJob < ApplicationJob
    queue_as :default

    MAX_ROUNDS = 20

    def perform(request_id, round = 1)
      request = OnlineOrderRequest.unscoped_by_company.find_by(id: request_id)
      return if request.nil? || !request.pending? || !request.call_center?

      Current.set(company: request.company) { Broadcast.inbox(request.location, nudge: true) }
      return if round >= MAX_ROUNDS

      self.class.set(wait: OnlineOrderRequest::ESCALATE_AFTER).perform_later(request_id, round + 1)
    end
  end
end
