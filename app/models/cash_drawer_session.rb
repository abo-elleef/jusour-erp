# frozen_string_literal: true

class CashDrawerSession < ApplicationRecord
  include Tenantable

  STATUSES = %w[open counted reconciled].freeze

  belongs_to :user
  belongs_to :treasury, optional: true
  belongs_to :location, optional: true
  # Where the opening float was carried in from (a safe, usually). The float is a
  # transfer between two treasuries, not income — without a source there is nothing
  # to credit it against.
  belongs_to :float_source_treasury, class_name: "Treasury", optional: true
  # Where the counted cash is handed over to at close — the safe it physically
  # goes into. Optional: a drawer can be counted without being banked yet.
  belongs_to :deposit_treasury, class_name: "Treasury", optional: true
  # A short drawer's payment voucher to the cashier (see Accounting::DrawerVarianceDocuments).
  belongs_to :shortage_voucher, class_name: "Voucher", optional: true
  belongs_to :shortage_waived_by, class_name: "User", optional: true
  # Who closed (counted) the drawer and when: the cashier at the POS, or a manager
  # from admin. A count correction keeps the original close; a reopen clears it.
  belongs_to :closed_by, class_name: "User", optional: true
  # An over drawer's Income, and a waived shortage's Expense, both point back here.
  has_many :variance_incomes, class_name: "Income", as: :source_record, dependent: nil
  has_many :variance_expenses, class_name: "Expense", as: :source_record, dependent: nil
  has_many :payments, dependent: :nullify
  has_many :print_logs, dependent: :destroy

  monetize :opening_float_cents
  monetize :expected_cash_cents, allow_nil: true
  monetize :counted_cash_cents, allow_nil: true
  monetize :variance_cents, allow_nil: true

  validates :session_date, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :treasury, presence: true
  validates :location, presence: true

  before_validation :assign_company_from_associations, on: :create

  scope :open, -> { where(status: "open") }

  def open?
    status == "open"
  end

  # No order is rung without an open drawer, so the drawer's lifetime is the
  # cashier's shift: from opening until now, or until it was closed.
  def order_window
    created_at..(open? ? Time.current : closed_time)
  end

  # When the drawer was closed. Falls back to updated_at only for a closed drawer
  # with no closed_at (none should have one after the backfill).
  def closed_time
    closed_at || updated_at
  end

  # The cashier's orders from this drawer session. There is no FK from orders to
  # the drawer, so they are matched by cashier, branch and time — plus any order
  # that took a payment in this drawer, whenever it was rung. Without those, an
  # older order paid here put money in the drawer's totals that no listed order
  # accounted for.
  def orders
    Order.where(user_id: user_id, location_id: location_id, created_at: order_window)
      .or(Order.where(id: payments.select(:order_id)))
  end

  # This drawer's orders with no ending yet (drafts with items, placed, ready).
  # The drawer cannot be closed while any is left — from the POS or from admin.
  def unfinished_orders
    Order.not_finalized.where(id: orders.select(:id))
  end

  # How many of this drawer's open orders are fully paid and only wait for the
  # cashier to complete them. Counted in SQL for the POS nav badge, which renders
  # on every register page. Same test as Order#fully_paid? (a total, all settled).
  def paid_unfinished_orders_count
    unfinished_orders.unscope(:order).where.not(total_cents: nil)
      .where.not(Order::BALANCE_DUE_SQL).count
  end

  # How many of this drawer's placed orders still owe money, for the POS nav badge.
  # Same "owes money" test as #unpaid_orders, minus drafts: a cart still being rung
  # up is not a debt yet.
  def unpaid_placed_orders_count
    Order.not_fully_paid.unscope(:order).where.not(status: "draft")
      .where(id: orders.select(:id)).count
  end

  # This drawer's orders that still owe money, finished or not. Same "owes money"
  # test as Collect Payment. Also blocks the close.
  def unpaid_orders
    Order.not_fully_paid.where(id: orders.select(:id)).includes(:payments).to_a
         .select { |order| order.amount_due_cents.positive? }
  end

  # Every order that stops this drawer closing, each once, oldest first.
  def orders_blocking_close
    (unfinished_orders.to_a + unpaid_orders).uniq(&:id).sort_by(&:created_at)
  end

  # The cash the books put in the drawer at close.
  #
  # A documented drawer books what it should have held (expected); the gap to the
  # count is booked on its own, as an Income or a voucher to the cashier, so the
  # safe still ends up holding exactly what was counted. A drawer reconciled
  # before that booked what was counted, and keeps doing so if it is ever
  # re-posted.
  def booked_cash_cents
    return 0 if counted_cash_cents.blank?

    variance_documented? ? expected_cash_cents.to_i : counted_cash_cents.to_i
  end

  # Cash taken during the session: what was booked beyond the float that was
  # already in the drawer when it opened. Can be negative when cash paid out
  # (refunds, drivers) beat cash taken.
  def cash_collected_cents
    return 0 if counted_cash_cents.blank?

    booked_cash_cents - opening_float_cents.to_i
  end

  # Everything in the drawer leaves at close, float included. Each open draws a
  # fresh float from its source, so a drawer that kept yesterday's would be holding
  # two by tomorrow. Negative only when the books say the drawer owes cash — then
  # the safe tops it up, so the drawer still ends at zero.
  def deposit_cents
    booked_cash_cents
  end

  # Where the over/short documents land: the treasury the cash physically ended in.
  def variance_treasury
    deposit_treasury || treasury
  end

  def over? = variance_documented? && variance_cents.to_i.positive?
  def short? = variance_documented? && variance_cents.to_i.negative?
  def shortage_waived? = shortage_waived_at.present?

  private

  def assign_company_from_associations
    self.company ||= user&.company || location&.company || treasury&.company
  end
end
