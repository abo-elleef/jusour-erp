# frozen_string_literal: true

# One entry in a customer's own timeline: a rep-logged touchpoint (call/
# whatsapp/email/meeting/note) after the customer exists — the twin of
# LeadActivity for the life after Lead#convert! — or a system entry for one of
# the customer's tickets being opened, resolved, closed or reopened (written by
# Ticket, linking to it). Not tenant-scoped directly — always reached through
# its customer, which is.
class CustomerActivity < ApplicationRecord
  LOGGABLE_TYPES = TimelineActivity::LOGGABLE_TYPES
  TICKET_TYPES = %w[ticket_opened ticket_resolved ticket_closed ticket_reopened].freeze
  ACTIVITY_TYPES = (LOGGABLE_TYPES + TICKET_TYPES).freeze

  include TimelineActivity

  belongs_to :customer
  belongs_to :ticket, optional: true
end
