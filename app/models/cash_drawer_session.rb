# frozen_string_literal: true

class CashDrawerSession < ApplicationRecord
  include Tenantable

  STATUSES = %w[open counted reconciled].freeze

  belongs_to :user
  belongs_to :treasury, optional: true
  belongs_to :location, optional: true
  has_many :payments, dependent: :nullify

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

  private

  def assign_company_from_associations
    self.company ||= user&.company || location&.company || treasury&.company
  end
end
