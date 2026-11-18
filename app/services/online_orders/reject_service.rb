# frozen_string_literal: true

module OnlineOrders
  # A cashier turns a self-order down, with a reason the customer sees (and an
  # optional note for staff only — the customer never sees it). With
  # block: true the phone can't self-order again until someone unblocks it on the
  # customer page (staff can still sell to them at the register).
  class RejectService
    def self.call(request:, user:, reason:, block: false, note: nil)
      reason = OnlineOrderRequest::REJECT_REASONS.include?(reason.to_s) ? reason.to_s : "other"
      done = request.with_lock do
        next false unless request.pending?

        request.record_check!(:decided)
        request.update!(status: "rejected", reject_reason: reason, reject_note: note.to_s.strip.first(500).presence,
                        blocked_phone: block, decided_by: user, decided_at: Time.current)
        if block
          FindOrCreateCustomer.call(request).block!(by: user, reason: I18n.t("pos.online_orders.block_reason",
                                                                             reason: I18n.t("pos.online_orders.reasons.#{reason}")))
        end
        true
      end
      Broadcast.inbox(request.location) if done
      done
    end
  end
end
