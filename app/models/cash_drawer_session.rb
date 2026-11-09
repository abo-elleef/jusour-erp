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

  # Cash actually taken during the session: everything counted at close beyond the
  # float that was already in the drawer when it opened.
  def cash_collected_cents
    return 0 if counted_cash_cents.blank?

    counted_cash_cents.to_i - opening_float_cents.to_i
  end

  # Everything in the drawer leaves at close, float included. Each open draws a
  # fresh float from its source, so a drawer that kept yesterday's would be holding
  # two by tomorrow.
  def deposit_cents
    counted_cash_cents.to_i
  end

  private

  def assign_company_from_associations
    self.company ||= user&.company || location&.company || treasury&.company
  end
end
