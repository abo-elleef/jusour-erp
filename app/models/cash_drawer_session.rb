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
  # cashier's shift: from opening until now, or until it was counted. There is no
  # closed_at, so a counted drawer ends at its last update.
  def order_window
    created_at..(open? ? Time.current : updated_at)
  end

  # The cashier's orders from this drawer session. There is no FK from orders to
  # the drawer, so they are matched by cashier, branch and time.
  def orders
    Order.where(user_id: user_id, location_id: location_id, created_at: order_window)
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
