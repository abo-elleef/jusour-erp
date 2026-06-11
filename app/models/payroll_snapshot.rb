# frozen_string_literal: true

class PayrollSnapshot < ApplicationRecord
  include Tenantable

  belongs_to :user
  belongs_to :finalized_by, class_name: "User"
  belongs_to :treasury, optional: true
  has_many :treasury_transactions, as: :source_record, dependent: :destroy

  validates :payroll_month, presence: true
  validates :user_id, uniqueness: { scope: :payroll_month }
  validates :base_salary_cents, :daily_rate_cents, :penalties_cents, :bonuses_cents, :net_pay_cents,
    :advances_cents, :remaining_pay_cents,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :finalized_at, presence: true
  validate :treasury_required_when_remaining_pay
  validate :paid_on_in_payroll_month

  before_validation :normalize_payroll_month

  def payout_required?
    remaining_pay_cents.positive?
  end

  scope :for_month, ->(month) { where(payroll_month: month.to_date.beginning_of_month) }

  private

  def normalize_payroll_month
    return if payroll_month.blank?

    self.payroll_month = payroll_month.to_date.beginning_of_month
  end

  def treasury_required_when_remaining_pay
    return unless payout_required?

    errors.add(:treasury, :blank) if treasury.blank?
    errors.add(:paid_on, :blank) if paid_on.blank?
  end

  def paid_on_in_payroll_month
    return if paid_on.blank? || payroll_month.blank?
    return if paid_on.beginning_of_month == payroll_month.beginning_of_month

    errors.add(:paid_on, :must_be_in_payroll_month)
  end
end
