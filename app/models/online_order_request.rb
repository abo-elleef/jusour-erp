# frozen_string_literal: true

# A customer's self-order from the public menu. It waits as `pending` until a
# cashier accepts it (and a real Order is built by OnlineOrders::AcceptService),
# rejects it, or it expires. See the self-ordering plan for why this is kept apart
# from Order: spam never touches order numbers, stock, reports or drawers.
class OnlineOrderRequest < ApplicationRecord
  include Tenantable

  STATUSES = %w[pending accepted rejected expired].freeze
  FULFILLMENTS = %w[delivery pickup].freeze
  REJECT_REASONS = %w[closed out_of_area item_unavailable suspicious no_answer other].freeze

  belongs_to :location
  belongs_to :customer, optional: true
  belongs_to :delivery_area, optional: true
  belongs_to :order, optional: true
  belongs_to :decided_by, class_name: "User", optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :fulfillment, inclusion: { in: FULFILLMENTS }
  validates :customer_name, :phone, :token, :expires_at, presence: true
  validates :address, presence: true, if: :delivery?
  validates :delivery_area, presence: true, if: :delivery?

  before_validation { self.token ||= SecureRandom.urlsafe_base64(18) }

  scope :pending, -> { where(status: "pending") }
  scope :recent_first, -> { order(created_at: :desc) }

  STATUSES.each do |name|
    define_method(:"#{name}?") { status == name }
  end

  def delivery? = fulfillment == "delivery"
  def pickup? = fulfillment == "pickup"

  def to_param = token

  def lines = quote.fetch("lines", [])

  # Past due and still waiting. ExpireJob flips these; the POS also hides them.
  def overdue?(now = Time.current) = pending? && expires_at <= now

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
    %w[status fulfillment customer_name phone created_at total_cents location_id customer_id reject_reason]
  end

  private

  def assign_company
    self.company ||= location&.company || Current.company
  end
end
