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

  # The follow-up date the rep picked on the log form. Blank means "use the
  # cadence" (occurred day + Setting.lead_follow_up_every_days).
  attribute :next_follow_up_on, :date

  before_validation :default_occurred_at
  after_create :move_lead_follow_up

  scope :recent, -> { order(occurred_at: :desc) }

  def loggable? = LOGGABLE_TYPES.include?(activity_type)

  # The date the log form pre-fills for this lead.
  def self.suggested_next_follow_up(lead, contact_on = Date.current)
    return unless lead.open?

    Lead.next_follow_up_date_after(contact_on)
  end

  private

  # A rep-logged contact moves the lead's next follow-up; system entries
  # (stage/assignment changes) never do, and closed leads keep none.
  def move_lead_follow_up
    return unless loggable? && lead.open?

    date = next_follow_up_on || self.class.suggested_next_follow_up(lead, occurred_at.in_time_zone.to_date)
    return if date.nil? || date == lead.next_follow_up_at

    # update_attribute: audited like any lead change, but an old lead that
    # fails a newer validation must not block logging the contact.
    lead.update_attribute(:next_follow_up_at, date)
  end

  def default_occurred_at
    self.occurred_at ||= Time.current
  end
end
