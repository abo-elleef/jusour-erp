# frozen_string_literal: true

class PayrollSnapshot < ApplicationRecord
  include Tenantable

  belongs_to :user
  belongs_to :finalized_by, class_name: "User"

  validates :payroll_month, presence: true
  validates :user_id, uniqueness: { scope: :payroll_month }
  validates :base_salary_cents, :daily_rate_cents, :penalties_cents, :bonuses_cents, :net_pay_cents,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :finalized_at, presence: true

  before_validation :normalize_payroll_month

  scope :for_month, ->(month) { where(payroll_month: month.to_date.beginning_of_month) }

  private

  def normalize_payroll_month
    return if payroll_month.blank?

    self.payroll_month = payroll_month.to_date.beginning_of_month
  end
end
