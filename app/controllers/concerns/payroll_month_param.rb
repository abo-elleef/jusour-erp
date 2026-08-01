# frozen_string_literal: true

# Shared YYYY-MM payroll month picker for attendance, payroll, and staff pages.
#
# When no month is passed, keep the previous calendar month selected through the
# 5th of the new month so closing work can finish before the picker flips.
module PayrollMonthParam
  extend ActiveSupport::Concern

  # Inclusive last day of the new month that still defaults to the previous month.
  GRACE_DAYS = 5

  def self.default_payroll_month(today: Date.current)
    month = today.day <= GRACE_DAYS ? today.prev_month : today
    month.beginning_of_month
  end

  class_methods do
    def default_payroll_month(today: Date.current)
      PayrollMonthParam.default_payroll_month(today: today)
    end
  end

  private

  def parse_payroll_month(param_key: :payroll_month)
    raw = params[param_key]
    if raw.present?
      Date.parse("#{raw}-01")
    else
      default_payroll_month
    end
  rescue ArgumentError
    default_payroll_month
  end

  def default_payroll_month(today: Date.current)
    PayrollMonthParam.default_payroll_month(today: today)
  end
end
