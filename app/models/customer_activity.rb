# frozen_string_literal: true

# One entry in a customer's own timeline: a rep-logged touchpoint (call/
# whatsapp/email/meeting/note) after the customer exists — the twin of
# LeadActivity for the life after Lead#convert!. Not tenant-scoped directly —
# always reached through its customer, which is.
class CustomerActivity < ApplicationRecord
  LOGGABLE_TYPES = TimelineActivity::LOGGABLE_TYPES
  ACTIVITY_TYPES = LOGGABLE_TYPES

  include TimelineActivity

  belongs_to :customer
end
