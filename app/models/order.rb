# frozen_string_literal: true

class Order < ApplicationRecord
  include AASM
  include Tenantable

  STATUSES = %w[draft submitted in_progress ready completed cancelled].freeze
  # The two states an order can be left in. Everything else is someone's unfinished
  # business, and a cashier cannot close a shift while any of it is theirs.
  FINAL_STATUSES = %w[completed cancelled].freeze
  ORDER_TYPES = %w[delivery pickup table].freeze

  # Advisory-lock namespace, so order numbering can never contend with another
  # part of the app that reaches for an advisory lock of its own.
  ORDER_NUMBER_LOCK_NAMESPACE = 8_301
  TABLE_LOCK_NAMESPACE = 8_302

  # Refunds are not deducted: a refunded payment settled the order when it was
  # taken, and re-opening a balance for it would send the cashier chasing money
  # the customer has already been given back. That includes a payment refunded in
  # full — its status is "refunded", and leaving it out made a fully refunded order
  # look as if it still owed its whole total.
  SETTLING_PAYMENT_STATUSES = %w[completed partially_refunded refunded].freeze

  BALANCE_DUE_SQL = <<~SQL.squish.freeze
    orders.total_cents > COALESCE((
      SELECT SUM(payments.amount_cents)
      FROM payments
      WHERE payments.order_id = orders.id
      AND payments.status IN ('completed', 'partially_refunded', 'refunded')
    ), 0)
  SQL

  belongs_to :customer, optional: true
  belongs_to :user
  belongs_to :location, optional: true
  belongs_to :workstation, optional: true
  belongs_to :staff_meal_user, class_name: "User", optional: true
  # The drawer the delivery fee was paid out of to the driver — see #apply_delivery_fee!.
  belongs_to :delivery_fee_drawer_session, class_name: "CashDrawerSession", optional: true
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
  monetize :delivery_fee_cents, allow_nil: false
  monetize :total_cents, allow_nil: true

  validates :order_number, presence: true,
                           uniqueness: { scope: %i[company_id location_id business_date] }
  validates :order_type, presence: true, inclusion: { in: ORDER_TYPES }
  validates :delivery_fee_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  before_validation :assign_business_date, on: :create
  before_validation :assign_order_number, on: :create
  before_save :clear_fulfillment_fields_for_type
  validate :table_must_be_free, if: :table_slot_changed?
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
        # No receipt here. The customer gets theirs when they pay, which is no
        # longer the same moment as this one.
        Loyalty::AwardPointsJob.perform_later(id)
        Inventory::DeductStockService.new(self).call
        AuditLogEntry.record!(action: "order.complete", record: self, user: user)
      end
    end

    # Ready is cancellable too: a customer can walk away while the food waits on
    # the pass. Missing it here made a void of a ready order silently do nothing.
    event :cancel do
      transitions from: %i[draft submitted in_progress ready], to: :cancelled
      after do
        AuditLogEntry.record!(action: "order.void", record: self, user: user)
        broadcast_to_kds
      end
    end
  end

  scope :open_drafts, -> { where(status: "draft") }
  # Orders still owed an ending. Drafts count — a cart with food in it is a sale
  # someone started — but an empty cart does not: there is nothing in it to finish.
  scope :not_finalized, -> {
    where.not(status: FINAL_STATUSES)
      .where("EXISTS (SELECT 1 FROM order_items WHERE order_items.order_id = orders.id)")
      .order(created_at: :asc)
  }
  # A table is busy from the first item until its order is completed or cancelled.
  # Only meaningful at branches with table service on; see Location#table_service.
  scope :open_table_orders, -> { not_finalized.where(order_type: "table").where.not(table_number: [nil, ""]) }
  scope :kitchen_queue, -> { where(status: %w[submitted in_progress ready]) }
  scope :awaiting_payment, -> {
    where.not(status: %w[draft cancelled]).order(created_at: :desc)
  }
  scope :on_date, ->(date) {
    where(created_at: BusinessDay.range(date))
  }
  scope :completed, -> { where(status: "completed") }
  scope :open_orders, -> { where(status: %w[submitted in_progress ready]) }
  scope :unpaid, -> {
    where.not(status: %w[draft cancelled]).where(BALANCE_DUE_SQL)
  }
  # Everything still owed money, drafts included. A part-paid cart and an order
  # rung up to be settled later are both draft — leaving drafts out hid them from
  # the only screen that exists to collect on them. Orders with no lines are still
  # excluded: an empty cart owes nothing.
  scope :not_fully_paid, -> {
    where.not(status: "cancelled")
      .where("EXISTS (SELECT 1 FROM order_items WHERE order_items.order_id = orders.id)")
      .where(BALANCE_DUE_SQL)
      .order(created_at: :desc)
  }

  # { "5" => order } for every busy table at the branch.
  def self.busy_tables(location)
    return {} unless location&.table_service?

    open_table_orders.where(location_id: location.id).includes(:user, :order_items).each_with_object({}) do |order, busy|
      busy[order.table_number.to_s] ||= order
    end
  end

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
    self.total_cents = (subtotal_cents || 0) - discount_cents + (tax_cents || 0) + tip_cents + delivery_fee_cents
    save!
  end

  def paid_cents
    payments.where(status: %w[completed partially_refunded]).sum(:amount_cents)
  end

  # Money taken on this order and not yet given back — what a refund can still return.
  def refundable_cents
    payments.where(status: %w[completed partially_refunded])
            .sum(Arel.sql("payments.amount_cents - payments.refunded_amount_cents")).to_i
  end

  # What the customer has paid toward this bill, refunds or not. This — not
  # paid_cents, which is the money actually kept — decides whether anything is owed.
  def settled_cents
    payments.where(status: SETTLING_PAYMENT_STATUSES).sum(:amount_cents)
  end

  def fully_paid?
    total_cents.present? && settled_cents >= total_cents
  end

  def amount_due_cents
    [(total_cents || 0) - settled_cents, 0].max
  end

  def delivery?
    order_type == "delivery"
  end

  # Delivery fees vary too much to price in advance, so the cashier types this
  # order's fee when collecting payment. It is fixed once any money is taken:
  # moving it afterwards would shift a total that payments were counted against.
  def delivery_fee_editable?
    delivery? && settled_cents.zero?
  end

  # The customer pays the fee with the order, but it is the driver's money, not
  # the restaurant's. On a cash order the driver keeps it out of what they
  # collected; on an InstaPay / Vodafone Cash order the cashier hands it over from
  # the drawer. Either way the drawer that takes the first payment ends up short
  # by the fee, so it is recorded as paid out of that drawer when the payment is
  # taken (Payment#charge_delivery_fee_to_drawer, read by
  # Accounting::SessionSalesSummary#driver_payout_cents). The fee can be saved
  # ahead of any payment, so an order out for delivery shows its full amount due.
  #
  # Returns false when the fee can no longer be changed (see above).
  def apply_delivery_fee!(cents)
    return false unless delivery_fee_editable?
    return true if cents == delivery_fee_cents

    self.delivery_fee_cents = cents
    recalculate_totals!
    true
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
      I18n.t("order.fulfillment.delivery")
    else
      I18n.t("order.fulfillment.pickup")
    end
  end

  # The other open order holding this order's table, or nil. Public because an empty
  # cart doesn't hold its table: the first item added has to ask again.
  def table_conflict
    return unless table? && table_number.present? && location&.table_service?
    return if FINAL_STATUSES.include?(status)

    lock_table!
    Order.open_table_orders.where(location_id: location_id, table_number: table_number.to_s)
         .where.not(id: id).first
  end

  def broadcast_to_kds
    Turbo::StreamsChannel.broadcast_refresh_to("kitchen_#{company_id}")
  end

  private

  def assign_business_date
    self.business_date ||= BusinessDay.for(created_at || Time.current, location: location)
  end

  # Numbers restart at 1 for each branch every business day, so a cashier can read
  # their own count off the ticket.
  #
  # The lock is an advisory one on the branch-day rather than a row lock on the
  # highest order: two registers reading the same maximum before either has
  # committed is exactly the race that hands both of them the same number, and no
  # lock on an existing row prevents it. It is released when the transaction ends.
  def assign_order_number
    return if order_number.present?

    lock_branch_day!
    last = Order.unscoped
                .where(company_id: company_id, location_id: location_id, business_date: business_date)
                .where("order_number ~ '^[0-9]+$'")
                .order(Arel.sql("order_number::integer DESC"))
                .limit(1)
                .pick(:order_number)
    self.order_number = (last.to_i + 1).to_s
  end

  def lock_branch_day!
    key = Zlib.crc32("#{company_id}:#{location_id}:#{business_date}")
    key -= 2**32 if key >= 2**31 # pg_advisory_xact_lock takes a signed int4
    self.class.connection.execute(
      "SELECT pg_advisory_xact_lock(#{ORDER_NUMBER_LOCK_NAMESPACE}, #{key})"
    )
  end

  def table_slot_changed?
    new_record? || will_save_change_to_table_number? || will_save_change_to_order_type? || will_save_change_to_location_id?
  end

  def table_must_be_free
    other = table_conflict
    return unless other

    errors.add(:table_number, I18n.t("order.errors.table_busy", table: table_number, number: other.order_number))
  end

  # Two registers claiming the same free table at the same moment would both pass
  # the check; serialising on the table closes that. Released when the transaction ends.
  def lock_table!
    key = Zlib.crc32("#{location_id}:#{table_number}")
    key -= 2**32 if key >= 2**31
    self.class.connection.execute("SELECT pg_advisory_xact_lock(#{TABLE_LOCK_NAMESPACE}, #{key})")
  end

  def generate_receipt_token
    self.receipt_token ||= SecureRandom.urlsafe_base64(16)
  end

  def clear_fulfillment_fields_for_type
    self.table_number = nil unless table?
    return if delivery?

    self.delivery_address = nil
    # An order switched away from delivery stops owing its fee. The total is
    # adjusted here rather than recalculated, since this runs inside a save.
    if delivery_fee_cents.positive?
      self.total_cents = total_cents.to_i - delivery_fee_cents
      self.delivery_fee_cents = 0
      self.delivery_fee_drawer_session_id = nil
    end
  end
end
