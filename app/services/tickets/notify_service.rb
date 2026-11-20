# frozen_string_literal: true

module Tickets
  # The three ticket notifications (Bazzar slice G1), each to one person and
  # never to whoever caused it:
  #
  #   ticket_assigned  — the assignee, when a ticket is opened on them or
  #                      handed to them.
  #   ticket_resolved  — the opener, when someone else resolves it.
  #   ticket_commented — the assignee, when someone else comments.
  #
  # Live push and the per-kind alert/popup/quiet level come from Notification
  # and Notifications::Levels like every other kind.
  class NotifyService
    def self.assigned(ticket, by:)
      deliver(ticket, ticket.assigned_user, "ticket_assigned", by: by)
    end

    def self.resolved(ticket, by:)
      deliver(ticket, ticket.opened_by, "ticket_resolved", by: by)
    end

    def self.commented(ticket, _comment, by:)
      deliver(ticket, ticket.assigned_user, "ticket_commented", by: by)
    end

    def self.deliver(ticket, recipient, message_key, by:)
      return if recipient.nil? || !recipient.active? || recipient.id == by&.id

      Notification.create!(
        recipient: recipient, company: ticket.company, notification_type: "sales",
        params: { message_key: message_key,
                  message_params: { ticket_id: ticket.id, ticket_number: ticket.display_number,
                                    subject: ticket.subject, by: by&.name.to_s }.deep_stringify_keys,
                  ticket_id: ticket.id }
      )
    end
    private_class_method :deliver
  end
end
