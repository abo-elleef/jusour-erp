# frozen_string_literal: true

class Order < ApplicationRecord
  include AASM
  include Tenantable

  STATUSES = %w[draft submitted in_progress ready completed cancelled].freeze
  ORDER_TYPES = %w[delivery pickup table].freeze

  belongs_to :customer, optional: true
  belongs_to :user
  belongs_to :location, optional: true
  has_many :order_items, dependent: :destroy
  has_many :order_discounts, dependent: :destroy
  has_many :payments, dependent: :destroy
  has_many :order_events, dependent: :destroy
  has_many :receipt_logs, dependent: :destroy
  has_many :print_logs, dependent: :destroy
  has_many :loyalty_transactions, dependent: :nullify

  monetize :subtotal_cents, allow_nil: true
  monetize :discount_cents, allow_nil: false
  monetize :tax_cents, allow_nil: true
  monetize :tip_cents, allow_nil: false
  monetize :total_cents, allow_nil: true

  validates :order_number, presence: true, uniqueness: { scope: :company_id }
  validates :order_type, presence: true, inclusion: { in: ORDER_TYPES }

  before_validation :assign_order_number, on: :create
  before_save :clear_fulfillment_fields_for_type
  before_create :generate_receipt_token

  aasm column: :status do
    state :draft, initial: true
    state :submitted
    state :in_progress
    state :ready
    state :completed
    state :cancelled

    event :submit do
      transitions from: :draft, to: :submitted
      after do
        Tax::CalculateService.call(self)
        broadcast_to_kds
      end
    end

    event :start_prep do
      transitions from: :submitted, to: :in_progress
      after { broadcast_to_kds }
    end

    event :mark_ready do
      transitions from: :in_progress, to: :ready
      after { broadcast_to_kds }
    end

    event :complete do
      transitions from: %i[ready submitted in_progress], to: :completed
      after do
        Loyalty::AwardPointsJob.perform_later(id)
        Inventory::DeductStockService.new(self).call
        Accounting::AutoCostService.new(self).call
        AuditLogEntry.record!(action: "order.complete", record: self, user: user)
        Printing::PrintReceiptJob.perform_later(id)
      end
    end

    event :cancel do
      transitions from: %i[draft submitted in_progress], to: :cancelled
      after do
        AuditLogEntry.record!(action: "order.void", record: self, user: user)
      end
    end
  end

  scope :open_drafts, -> { where(status: "draft") }
  scope :kitchen_queue, -> { where(status: %w[submitted in_progress ready]) }
  scope :awaiting_payment, -> {
    where.not(status: %w[draft cancelled]).order(created_at: :desc)
  }
  scope :on_date, ->(date) {
    day = date.is_a?(Date) ? date : Date.parse(date.to_s)
    where(created_at: day.beginning_of_day..day.end_of_day)
  }
  scope :completed, -> { where(status: "completed") }
  scope :open_orders, -> { where(status: %w[submitted in_progress ready]) }
  scope :unpaid, -> {
    where.not(status: %w[draft cancelled])
      .where(
        "orders.total_cents > COALESCE((
          SELECT SUM(payments.amount_cents)
          FROM payments
          WHERE payments.order_id = orders.id
          AND payments.status IN ('completed', 'partially_refunded')
        ), 0)"
      )
  }

  def self.ransackable_attributes(_auth_object = nil)
    %w[status order_number order_type created_at user_id customer_id total_cents subtotal_cents]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[user customer]
  end

  def recalculate_totals!
    order_items.reset
    subtotal = order_items.sum(&:line_total_cents)
    discount = order_discounts.sum(:amount_cents)
    self.subtotal_cents = subtotal
    self.discount_cents = discount
    Tax::CalculateService.call(self)
    self.total_cents = (subtotal_cents || 0) - discount_cents + (tax_cents || 0) + tip_cents
    save!
  end

  def paid_cents
    payments.where(status: %w[completed partially_refunded]).sum(:amount_cents)
  end

  def fully_paid?
    total_cents.present? && paid_cents >= total_cents
  end

  def amount_due_cents
    [(total_cents || 0) - paid_cents, 0].max
  end

  def delivery?
    order_type == "delivery"
  end

  def pickup?
    order_type == "pickup"
  end

  def table?
    order_type == "table"
  end

  def order_type_label
    I18n.t("order.types.#{order_type}", default: order_type.humanize)
  end

  def fulfillment_summary
    case order_type
    when "table"
      if table_number.present?
        I18n.t("order.fulfillment.table_number", number: table_number)
      else
        I18n.t("order.fulfillment.table")
      end
    when "delivery"
      delivery_address.presence || I18n.t("order.fulfillment.delivery")
    else
      I18n.t("order.fulfillment.pickup")
    end
  end

  def broadcast_to_kds
    Turbo::StreamsChannel.broadcast_refresh_to("kitchen_#{company_id}")
  end

  private

  def assign_order_number
    return if order_number.present?

    last = Order.where("order_number LIKE ?", "ORD-%").order(:created_at).last
    num = last ? last.order_number.delete_prefix("ORD-").to_i + 1 : 1
    self.order_number = format("ORD-%04d", num)
  end

  def generate_receipt_token
    self.receipt_token ||= SecureRandom.urlsafe_base64(16)
  end

  def clear_fulfillment_fields_for_type
    self.table_number = nil unless table?
    self.delivery_address = nil unless delivery?
  end
end
