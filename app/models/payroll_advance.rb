# frozen_string_literal: true

class PayrollAdvance < ApplicationRecord
  include Tenantable

  SLOTS = %w[mid_month end_month].freeze
  SLOT_DAYS = { "mid_month" => 15, "end_month" => 25 }.freeze
  MID_MONTH_MAX_SALARY_RATIO = 0.5

  belongs_to :user
  belongs_to :treasury
  belongs_to :paid_by, class_name: "User"
  has_many :treasury_transactions, as: :source_record, dependent: :destroy

  monetize :amount_cents

  validates :payroll_month, :advance_slot, :paid_on, presence: true
  validates :advance_slot, inclusion: { in: SLOTS }
  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :user_id, uniqueness: { scope: %i[payroll_month advance_slot] }
  validate :salary_required
  validate :paid_on_in_payroll_month
  validate :payroll_not_finalized
  validate :within_advance_limits

  before_validation :normalize_payroll_month

  scope :for_month, ->(month) { where(payroll_month: month.to_date.beginning_of_month) }
  scope :ordered, -> { order(paid_on: :asc, created_at: :asc) }

  def slot_label
    I18n.t("staff.payroll.advances.slots.#{advance_slot}")
  end

  def self.available_slots_for(user, payroll_month)
    taken = user.payroll_advances.for_month(payroll_month).pluck(:advance_slot)
    SLOTS - taken
  end

  def self.max_amount_cents_for(user, payroll_month, advance_slot)
    summary = Accounting::MonthlyPayrollService.new(user, payroll_month).build_calculated
    gross_net = summary.net_pay_cents
    advances_so_far = user.payroll_advances.for_month(payroll_month).sum(:amount_cents)
    remaining = gross_net - advances_so_far
    return 0 if remaining <= 0

    case advance_slot
    when "mid_month"
      [remaining, (user.monthly_salary_cents * MID_MONTH_MAX_SALARY_RATIO).round].min
    when "end_month"
      remaining
    else
      0
    end
  end

  private

  def normalize_payroll_month
    return if payroll_month.blank?

    self.payroll_month = payroll_month.to_date.beginning_of_month
  end

  def salary_required
    return if user&.monthly_salary_cents.to_i.positive?

    errors.add(:base, :salary_required)
  end

  def paid_on_in_payroll_month
    return if paid_on.blank? || payroll_month.blank?
    return if paid_on.beginning_of_month == payroll_month.beginning_of_month

    errors.add(:paid_on, :must_be_in_payroll_month)
  end

  def payroll_not_finalized
    return if user.blank? || payroll_month.blank?
    return unless PayrollSnapshot.exists?(user: user, payroll_month: payroll_month)

    errors.add(:base, :payroll_finalized)
  end

  def within_advance_limits
    return if user.blank? || payroll_month.blank? || advance_slot.blank? || amount_cents.blank?

    max_allowed = self.class.max_amount_cents_for(user, payroll_month, advance_slot)
    return if amount_cents <= max_allowed

    errors.add(:amount_cents, :exceeds_limit, limit: max_allowed)
  end
end
