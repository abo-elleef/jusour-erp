# frozen_string_literal: true

class PrintLog < ApplicationRecord
  PRINT_TYPES = %w[receipt kitchen bar expo pick_station station drawer_close].freeze
  STATUSES = %w[pending sent failed skipped].freeze

  # A job is either an order's ticket or a drawer's closing slip.
  belongs_to :order, optional: true
  belongs_to :cash_drawer_session, optional: true
  # The register that should print it. Only set for drawer slips — an order's receipt
  # takes its register from the order itself.
  belongs_to :workstation, optional: true
  belongs_to :printer, optional: true

  validates :print_type, inclusion: { in: PRINT_TYPES }
  validates :status, inclusion: { in: STATUSES }
  validate :belongs_to_one_subject

  def subject
    order || cash_drawer_session
  end

  def company_id
    subject&.company_id
  end

  # How long a register's claim holds. Long enough to cover a print and its retries,
  # short enough that a register which claimed and then died doesn't strand the job.
  CLAIM_TTL = 2.minutes

  # Jobs nobody is currently printing — what a page asks for when it recovers.
  scope :unclaimed, -> { where("print_logs.claimed_at IS NULL OR print_logs.claimed_at < ?", CLAIM_TTL.ago) }

  # Atomically take this job for `client`. True for the first caller and, repeatedly,
  # for that same caller; false for everyone else, and for a job already finished.
  # One UPDATE decides it, so two registers can never both win.
  def self.claim!(id, client)
    where(id: id, status: "pending")
      .where("claimed_at IS NULL OR claimed_at < :ttl OR claimed_by = :client",
             ttl: CLAIM_TTL.ago, client: client.to_s)
      .update_all(claimed_at: Time.current, claimed_by: client.to_s) == 1
  end

  private

  def belongs_to_one_subject
    return if order_id.present? ^ cash_drawer_session_id.present?

    errors.add(:base, "a print job belongs to an order or to a cash drawer session, not both or neither")
  end
end
