# frozen_string_literal: true

# LEGACY — read-only. Advances are gone: money handed to an employee ahead of
# payroll is now an ordinary payment voucher with the employee as its party,
# and it lands on their own account (User#account_code) like every other
# payment to them.
#
# Kept only so payroll:convert_to_staff_accounts can read the old rows and
# record which voucher each one became (converted_voucher_id). Nothing in the
# app writes here any more. Drop the table, this file, and PayrollAdvance in
# PaymentAllocation::SETTLEABLE_TYPES / SettledRecordsHelper once production
# has run the conversion and baked.
class PayrollAdvance < ApplicationRecord
  include Tenantable

  belongs_to :user
  belongs_to :treasury
  belongs_to :paid_by, class_name: "User"
  belongs_to :converted_voucher, class_name: "Voucher", optional: true
  has_many :payment_allocations, as: :settles

  scope :unconverted, -> { where(converted_voucher_id: nil) }
end
