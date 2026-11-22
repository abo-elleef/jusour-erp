# frozen_string_literal: true

# A customer's self-order from the public menu. It waits as `pending` until a
# cashier accepts it (and a real Order is built by OnlineOrders::AcceptService),
# rejects it, or it expires. See the self-ordering plan for why this is kept apart
# from Order: spam never touches order numbers, stock, reports or drawers.
#
# A call-center request (channel "call_center") is the same thing typed by a staff
# member away from the branch (phone / WhatsApp room). It is accepted the same way,
# so the order belongs to the branch cashier and prints on the branch's printers.
# It never expires on its own (the customer was already told yes); the branch is
# nudged again while it waits (OnlineOrders::EscalateJob), and the agent who sent it
# may cancel it until a cashier decides.
class OnlineOrderRequest < ApplicationRecord
  include Tenantable

  STATUSES = %w[pending accepted rejected expired cancelled].freeze
  CHANNELS = %w[public call_center].freeze
  # A call-center request waiting longer than this is "late": the branch badge
  # rings again and the agent is told to phone the branch.
  ESCALATE_AFTER = 3.minutes
  FULFILLMENTS = %w[delivery pickup].freeze
  REJECT_REASONS = %w[closed out_of_area item_unavailable suspicious no_answer other].freeze
  # The payment screenshot is shown to the cashier in the browser, so only formats
  # every browser draws (iPhone screenshots are PNG; HEIC would not display).
  PROOF_CONTENT_TYPES = %w[image/jpeg image/png image/webp].freeze
  PROOF_MAX_SIZE = 10.megabytes

  belongs_to :location
  belongs_to :customer, optional: true
  belongs_to :delivery_area, optional: true
  belongs_to :order, optional: true
  belongs_to :decided_by, class_name: "User", optional: true
  belongs_to :created_by, class_name: "User", optional: true

  # Screenshot of the customer's transfer, required when the method they chose
  # is "pay before ordering" (prepaid). Kept after the decision as the record.
  has_one_attached :payment_proof_image

  validates :status, inclusion: { in: STATUSES }
  validates :fulfillment, inclusion: { in: FULFILLMENTS }
  validates :channel, inclusion: { in: CHANNELS }
  validates :customer_name, :phone, :token, presence: true
  validates :expires_at, presence: true, unless: :call_center?
  validates :created_by, presence: true, if: :call_center?
  validates :address, presence: true, if: :delivery?
  validates :delivery_area, presence: true, if: :delivery?
  validates :payment_method, inclusion: { in: OnlinePaymentMethod::METHODS }
  validates :payment_proof_image, presence: true, if: :prepaid?

  before_validation { self.token ||= SecureRandom.urlsafe_base64(18) }

  scope :pending, -> { where(status: "pending") }
  scope :recent_first, -> { order(created_at: :desc) }
  # Still waiting for a cashier: pending and not past its expiry (call-center
  # requests have none).
  scope :waiting, ->(now = Time.current) { pending.where("online_order_requests.expires_at IS NULL OR online_order_requests.expires_at > ?", now) }
  scope :call_center, -> { where(channel: "call_center") }

  STATUSES.each do |name|
    define_method(:"#{name}?") { status == name }
  end

  def delivery? = fulfillment == "delivery"
  def pickup? = fulfillment == "pickup"
  def call_center? = channel == "call_center"

  # A call-center request a cashier hasn't answered for ESCALATE_AFTER.
  def late?(now = Time.current) = call_center? && pending? && created_at <= now - ESCALATE_AFTER

  # Whether a file is a screenshot the cashier can look at (type and size).
  def self.acceptable_proof?(file)
    file.respond_to?(:content_type) && PROOF_CONTENT_TYPES.include?(file.content_type) &&
      file.size.to_i.between?(1, PROOF_MAX_SIZE)
  end

  def to_param = token

  def lines = quote.fetch("lines", [])

  # Past due and still waiting. ExpireJob flips these; the POS also hides them.
  def overdue?(now = Time.current) = pending? && expires_at.present? && expires_at <= now

  # The "Who is this?" check saved when the request came in (:created) or was
  # accepted/rejected (:decided); nil for requests from before it was saved.
  def check_snapshot(stage)
    data = checks[stage.to_s]
    data.present? ? OnlineOrders::CustomerCheck::Snapshot.new(self, data) : nil
  end

  def record_check!(stage, now: Time.current)
    update_columns(checks: checks.merge(stage.to_s => OnlineOrders::CustomerCheck.new(self, now: now).to_snapshot))
  end

  # Previous requests from the same phone that a cashier turned down.
  def previous_rejections_count
    self.class.where(phone: phone, status: "rejected").where.not(id: id).count
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[status fulfillment customer_name phone created_at total_cents location_id customer_id reject_reason payment_method prepaid channel created_by_id]
  end

  private

  def assign_company
    self.company ||= location&.company || Current.company
  end
end
