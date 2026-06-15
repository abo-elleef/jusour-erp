# frozen_string_literal: true

class StockTransfer < ApplicationRecord
  include Tenantable

  STATUSES = %w[requested awaiting_receipt partially_received completed cancelled].freeze

  belongs_to :from_location, class_name: "Location"
  belongs_to :to_location, class_name: "Location"
  belongs_to :requested_by, class_name: "User"
  belongs_to :sent_by, class_name: "User", optional: true
  belongs_to :received_by, class_name: "User", optional: true
  has_many :stock_transfer_lines, dependent: :destroy
  has_many :stock_transfer_shipments, dependent: :destroy
  has_many :ingredients, through: :stock_transfer_lines
  has_many :stock_adjustments, dependent: :nullify

  accepts_nested_attributes_for :stock_transfer_lines,
    allow_destroy: true,
    reject_if: proc { |attrs| attrs["ingredient_id"].blank? }

  validates :transfer_number, presence: true, uniqueness: { scope: :company_id }
  validates :status, inclusion: { in: STATUSES }
  validates :requested_at, presence: true
  validate :locations_must_differ
  validate :locations_must_be_active
  validate :locations_must_share_company

  scope :recent, -> { order(requested_at: :desc, created_at: :desc) }
  scope :pending_send, -> { where(status: %w[requested partially_received]) }
  scope :pending_receive, -> { where(status: "awaiting_receipt") }

  before_validation :assign_transfer_number, on: :create
  before_validation :stamp_requested_at, on: :create

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

  def editable?
    requested?
  end

  def can_send?
    requested? || partially_received?
  end

  def can_confirm_receipt?
    awaiting_receipt? && current_shipment.present?
  end

  def fully_fulfilled?
    stock_transfer_lines.all?(&:fulfilled?)
  end

  def current_shipment
    stock_transfer_shipments.in_transit.order(:sequence).last
  end

  private

  def assign_transfer_number
    return if transfer_number.present?

    date_prefix = Date.current.strftime("%Y-%m-%d")
    prefix = "ST-#{date_prefix}-"
    last_seq = self.class.unscoped_by_company
      .where(company_id: company_id)
      .where("transfer_number LIKE ?", "#{prefix}%")
      .count
    self.transfer_number = format("%s%04d", prefix, last_seq + 1)
  end

  def stamp_requested_at
    self.requested_at ||= Time.current
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
