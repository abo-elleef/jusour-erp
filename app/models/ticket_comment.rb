# frozen_string_literal: true

# One entry on a ticket's timeline: a person's comment (with optional images),
# or a system entry for a status change or reassignment (see Ticket). System
# entries keep their facts in `data` and are worded when shown, so each reader
# sees them in their own language. Not tenant-scoped directly — always reached
# through its ticket, which is.
class TicketComment < ApplicationRecord
  KINDS = %w[comment status_change assignment_change].freeze

  belongs_to :ticket, touch: true
  belongs_to :user, optional: true

  has_many_attached :images

  validates :kind, inclusion: { in: KINDS }
  validates :body, presence: true, if: -> { comment? && !images.attached? }
  validate :images_acceptable

  scope :chronological, -> { order(:created_at, :id) }

  def comment? = kind == "comment"
  def system? = !comment?

  private

  def images_acceptable
    TicketImages.validate(self, images)
  end
end
