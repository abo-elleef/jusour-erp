# frozen_string_literal: true

# One entry in a lead's timeline: a rep-logged touchpoint (call/whatsapp/email/
# meeting/note) or a system-logged stage/assignment change (see Lead's
# #change_stage!/#reassign!/#convert!/#mark_lost!). Not tenant-scoped directly —
# always reached through its lead, which is.
class LeadActivity < ApplicationRecord
  ACTIVITY_TYPES = %w[call whatsapp email meeting note stage_change assignment_change].freeze
  LOGGABLE_TYPES = %w[call whatsapp email meeting note].freeze

  belongs_to :lead
  belongs_to :user, optional: true

  validates :activity_type, inclusion: { in: ACTIVITY_TYPES }
  validates :note, presence: true, if: -> { LOGGABLE_TYPES.include?(activity_type) }

  before_validation :default_occurred_at

  scope :recent, -> { order(occurred_at: :desc) }

  private

  def default_occurred_at
    self.occurred_at ||= Time.current
  end
end
