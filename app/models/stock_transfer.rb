# frozen_string_literal: true

class StockTransfer < ApplicationRecord
  include Tenantable

  STATUSES = %w[draft requested awaiting_receipt partially_received completed cancelled].freeze

  # Statuses that still need someone to act on them — the shared work queue the
  # index lands on. Drafts are deliberately excluded: an unfinished request is
  # authoring in progress, not work anyone else can pick up.
  IN_PROGRESS_STATUSES = %w[requested awaiting_receipt partially_received].freeze

  # An awaiting_receipt transfer older than this has stock sitting in limbo
  # between the two locations, so the index flags it.
  AGING_RECEIPT_DAYS = 7

  belongs_to :from_location, class_name: "Location"
  belongs_to :to_location, class_name: "Location"
  belongs_to :requested_by, class_name: "User"
  # The template this transfer was built from, when it wasn't assembled by hand.
  # Nullable, and nulls out if the template is later deleted.
  belongs_to :stock_transfer_template, optional: true
  belongs_to :sent_by, class_name: "User", optional: true
  belongs_to :received_by, class_name: "User", optional: true
  belongs_to :closed_short_by, class_name: "User", optional: true
  has_many :stock_transfer_lines, -> { order(:position, :created_at) }, dependent: :destroy, inverse_of: :stock_transfer
  has_many :stock_transfer_shipments, dependent: :destroy
  has_many :ingredients, through: :stock_transfer_lines
  has_many :stock_adjustments, dependent: :nullify

  # A Symbol, not a proc, so the check runs in instance context and can see
  # `draft?`. Drafts keep ingredient-only rows, otherwise "save and finish
  # later" would silently drop every line whose quantity isn't typed in yet.
  accepts_nested_attributes_for :stock_transfer_lines,
    allow_destroy: true,
    reject_if: :reject_transfer_line?

  validates :transfer_number, presence: true, uniqueness: { scope: :company_id }
  validates :status, inclusion: { in: STATUSES }
  validates :requested_at, presence: true
  validates :transferred_on, presence: true
  validate :locations_must_differ
  validate :locations_must_be_active
  validate :locations_must_share_company
  validate :transferred_on_not_in_the_future

  scope :recent, -> { order(transferred_on: :desc, requested_at: :desc, created_at: :desc) }
  scope :pending_send, -> { where(status: %w[requested partially_received]) }
  scope :pending_receive, -> { where(status: "awaiting_receipt") }
  scope :in_progress, -> { where(status: IN_PROGRESS_STATUSES) }
  scope :drafts, -> { where(status: "draft") }
  scope :on_date, ->(date) { where(transferred_on: date) }

  before_validation :assign_transfer_number, on: :create
  before_validation :assign_transferred_on
  before_validation :sync_requested_at_from_transfer_date

  def draft?
    status == "draft"
  end

  def requested?
    status == "requested"
  end

  def awaiting_receipt?
    status == "awaiting_receipt"
  end

  def partially_received?
    status == "partially_received"
  end

  def completed?
    status == "completed"
  end

  def cancelled?
    status == "cancelled"
  end

  def from_template?
    stock_transfer_template_id.present?
  end

  def editable?
    draft? || requested?
  end

  def can_submit?
    draft?
  end

  # Only drafts are destroyable. Once submitted, a transfer is an audit record
  # and gets cancelled instead.
  def discardable?
    draft?
  end

  # Sent but still not received after AGING_RECEIPT_DAYS — stock is in limbo.
  def stale_awaiting_receipt?(as_of: Date.current)
    return false unless awaiting_receipt?
    return false if transferred_on.blank?

    transferred_on < as_of - AGING_RECEIPT_DAYS
  end

  # Finished with a shortfall accepted, rather than everything having arrived. Shares
  # the `completed` status so the Open queue clears, but stays distinguishable.
  def closed_short?
    closed_short_at.present?
  end

  # Only from partially_received: while a shipment is in transit the outcome is not
  # known yet, and a transfer that has shipped nothing should be cancelled instead.
  def can_close_short?
    partially_received?
  end

  # Lines that never got everything they asked for. The basis of the shortfall
  # record — reconstructable before, but nothing surfaced it.
  def short_lines
    stock_transfer_lines.reject(&:fulfilled?)
  end

  # Any in-progress status. A second batch may leave before the first is confirmed —
  # each dispatch opens its own shipment, and receive/void act on a named shipment
  # rather than "the latest open one".
  def can_send?
    IN_PROGRESS_STATUSES.include?(status)
  end

  def open_shipments
    stock_transfer_shipments.in_transit.ordered
  end

  def can_confirm_receipt?
    open_shipments.any?
  end

  def can_void_in_transit_shipment?
    open_shipments.any?
  end

  # Where the transfer stands, given its shipments. Shared by confirm and void so the
  # two can never disagree — they previously each carried their own copy of this.
  def recalculated_status
    return "awaiting_receipt" if stock_transfer_shipments.in_transit.exists?
    return "completed" if fully_fulfilled?

    if stock_transfer_lines.any? { |line| line.quantity_received.positive? || line.quantity_sent.positive? }
      "partially_received"
    else
      "requested"
    end
  end

  # Reloaded deliberately. Callers update lines through other associations (a
  # shipment line's stock_transfer_line), so a stock_transfer_lines collection loaded
  # earlier in the same request reads stale quantities — and this decides whether the
  # transfer is marked completed. Called once per send/receive, so the query is cheap.
  def fully_fulfilled?
    stock_transfer_lines.reload.all?(&:fulfilled?)
  end

  # Kept for callers that only care that *something* is open. Prefer open_shipments
  # and an explicit shipment id — with several open at once, "the latest" is arbitrary.
  def current_shipment
    stock_transfer_shipments.in_transit.order(:sequence).last
  end

  # Timestamp on `transferred_on` at the current clock time, so late-entered
  # send/receive still land on the physical transfer day.
  def occurred_at(now: Time.current)
    date = transferred_on || Date.current
    now.in_time_zone.change(year: date.year, month: date.month, day: date.day)
  end

  private

  def assign_transfer_number
    return if transfer_number.present?

    self.transfer_number = self.class.next_transfer_number(company: company || Current.company)
  end

  # "ST-<year>-<sequence>", e.g. ST-2026-00001. Company-wide sequence that resets
  # each year; legacy dated numbers (ST-YYYY-MM-DD-NNNN) are ignored so the yearly
  # series starts clean. (A class method, so `private` above doesn't hide it.)
  def self.next_transfer_number(company: Current.company, year: Date.current.year)
    prefix = "ST-#{year}-"
    return "#{prefix}00001" if company.blank?

    max_seq = unscoped_by_company
      .where(company_id: company.id)
      .where("transfer_number ~ ?", "^ST-#{year}-[0-9]+$")
      .maximum(Arel.sql("CAST(SUBSTRING(transfer_number FROM #{prefix.length + 1}) AS INTEGER)"))

    format("%s%05d", prefix, (max_seq || 0) + 1)
  end

  # `send`-invoked by accepts_nested_attributes_for, so private is fine.
  def reject_transfer_line?(attrs)
    return true if attrs["ingredient_id"].blank?
    # Drafts keep a row as soon as an ingredient is picked; the quantity can
    # come later. Submitting re-validates and demands a positive quantity.
    return false if draft?

    qty = attrs["quantity_requested_input"].presence || attrs["quantity_requested"]
    qty.blank? || qty.to_d <= 0
  end

  def assign_transferred_on
    self.transferred_on ||= Date.current
  end

  def sync_requested_at_from_transfer_date
    return unless new_record? || requested? || draft?
    return if transferred_on.blank?

    self.requested_at = occurred_at
  end

  def transferred_on_not_in_the_future
    return if transferred_on.blank? || transferred_on <= Date.current

    errors.add(:transferred_on, :in_the_future)
  end

  def locations_must_differ
    return if from_location_id.blank? || to_location_id.blank?
    return unless from_location_id == to_location_id

    errors.add(:to_location_id, :same_as_source)
  end

  def locations_must_be_active
    errors.add(:from_location_id, :inactive) if from_location && !from_location.active?
    errors.add(:to_location_id, :inactive) if to_location && !to_location.active?
  end

  def locations_must_share_company
    return if from_location.blank? || to_location.blank?

    errors.add(:to_location_id, :invalid) unless from_location.company_id == to_location.company_id
  end
end
