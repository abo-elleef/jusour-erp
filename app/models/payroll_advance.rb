# frozen_string_literal: true

class PayrollAdvance < ApplicationRecord
  include Tenantable
  include MoneyInputs

  money_input :amount_cents

  belongs_to :user
  belongs_to :treasury
  belongs_to :paid_by, class_name: "User"
  has_many :treasury_transactions, as: :source_record, dependent: :destroy

  monetize :amount_cents

  validates :payroll_month, :paid_on, presence: true
  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }
  validate :salary_required
  validate :payroll_not_finalized
  validate :within_advance_limits

  # The advance date drives which month it is deducted from.
  before_validation :derive_payroll_month_from_paid_on

  scope :for_month, ->(month) { where(payroll_month: month.to_date.beginning_of_month) }
  scope :ordered, -> { order(paid_on: :asc, created_at: :asc) }

  # Cap advances at the employee's configured monthly salary for the month,
  # not attendance-based net pay. Remaining room shrinks as advances are paid.
  def self.max_amount_cents_for(user, payroll_month)
    advances_so_far = user.payroll_advances.for_month(payroll_month).sum(:amount_cents)
    remaining = user.monthly_salary_cents.to_i - advances_so_far
    [remaining, 0].max
  end

  private

  def derive_payroll_month_from_paid_on
    return if paid_on.blank?

    self.payroll_month = paid_on.to_date.beginning_of_month
  end

  def salary_required
    return if user&.monthly_salary_cents.to_i.positive?

    errors.add(:base, :salary_required)
  end

  def payroll_not_finalized
    return if user.blank? || payroll_month.blank?
    return unless PayrollSnapshot.exists?(user: user, payroll_month: payroll_month)

    errors.add(:base, :payroll_finalized)
  end

  def within_advance_limits
    return if user.blank? || payroll_month.blank? || amount_cents.blank?

    max_allowed = self.class.max_amount_cents_for(user, payroll_month)
    return if amount_cents <= max_allowed

    errors.add(:amount_cents, :exceeds_limit, limit: max_allowed)
  end
end
