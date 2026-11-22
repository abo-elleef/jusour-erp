# frozen_string_literal: true

module OnlineOrders
  # The call-center agent who sent a request takes it back (the customer changed
  # their mind, or it was typed wrong) — only while no cashier has decided on it.
  # Nothing exists outside the request yet, so there is nothing else to undo.
  class CancelService
    def self.call(request:, user:)
      return false unless request.call_center? && request.created_by_id == user.id

      done = request.with_lock do
        next false unless request.pending?

        request.update!(status: "cancelled", decided_by: user, decided_at: Time.current)
      end
      Broadcast.inbox(request.location) if done
      done
    end
  end
end
