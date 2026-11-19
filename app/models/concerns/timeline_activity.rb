# frozen_string_literal: true

# Shared by the timeline entry models (LeadActivity, CustomerActivity): a
# rep-logged touchpoint — call/whatsapp/email/meeting/note — that needs a note,
# stamped with when it happened. Each model lists its own ACTIVITY_TYPES (the
# loggable ones plus any it logs itself, e.g. a lead's stage changes).
module TimelineActivity
  extend ActiveSupport::Concern

  LOGGABLE_TYPES = %w[call whatsapp email meeting note].freeze

  included do
    belongs_to :user, optional: true

    validates :activity_type, inclusion: { in: ->(record) { record.class::ACTIVITY_TYPES } }
    validates :note, presence: true, if: :loggable?

    before_validation :default_occurred_at

    scope :recent, -> { order(occurred_at: :desc, created_at: :desc) }
  end

  def loggable? = LOGGABLE_TYPES.include?(activity_type)

  private

  def default_occurred_at
    self.occurred_at ||= Time.current
  end
end
