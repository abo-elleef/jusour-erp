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

  # What a register may (re)start: free jobs, plus the ones it holds itself. The
  # second part is how a page that was reloaded mid-print picks its own job back up
  # instead of waiting out the lease.
  scope :claimable_by, lambda { |client|
    where("print_logs.claimed_at IS NULL OR print_logs.claimed_at < :ttl OR print_logs.claimed_by = :client",
          ttl: CLAIM_TTL.ago, client: client.to_s)
  }

  # Failed jobs nobody has since printed successfully (same order, ticket type and
  # printer) — what the cashier still needs to act on.
  FAILED_WINDOW = 12.hours
  scope :needs_attention, lambda {
    where(status: "failed").where("print_logs.updated_at > ?", FAILED_WINDOW.ago).where(
      "NOT EXISTS (SELECT 1 FROM print_logs later WHERE later.status = 'sent' " \
      "AND later.print_type = print_logs.print_type " \
      "AND later.order_id IS NOT DISTINCT FROM print_logs.order_id " \
      "AND later.cash_drawer_session_id IS NOT DISTINCT FROM print_logs.cash_drawer_session_id " \
      "AND later.printer_id IS NOT DISTINCT FROM print_logs.printer_id " \
      "AND later.created_at > print_logs.created_at)"
    )
  }

  # The Turbo stream the job is announced on. Receipts for a named register go to
  # that register only; everything else is shared across the branch.
  def stream_name
    company = company_id
    location = order&.location_id || cash_drawer_session&.location_id
    register = order&.workstation_id if print_type == "receipt"
    register = workstation_id if print_type == "drawer_close"
    return "pos_prints_#{company}" if location.blank?

    register.present? ? "pos_prints_#{company}_#{location}_#{register}" : "pos_prints_#{company}_#{location}"
  end

  # Put a failed job back in the queue and tell the registers. The bytes are rebuilt
  # when a register fetches it, so a job that failed while building is retried with
  # the current code and data.
  def requeue!
    return false unless status == "failed"

    update!(status: "pending", error_message: nil, claimed_at: nil, claimed_by: nil)
    Turbo::StreamsChannel.broadcast_append_to(
      stream_name,
      target: "client-print-queue",
      partial: "pos/client_prints/job",
      locals: { print_log: self, order: order }.compact
    )
    true
  end

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
