# frozen_string_literal: true

class Treasury < ApplicationRecord
  include Tenantable

  TYPES = %w[cash_drawer bank safe petty_cash mobile_wallet other supplier_ap].freeze

  has_many :treasury_transactions, dependent: :destroy
  has_many :expenses, dependent: :restrict_with_error
  has_many :incomes, dependent: :restrict_with_error
  has_many :payroll_advances, dependent: :restrict_with_error
  has_many :payroll_snapshots, dependent: :restrict_with_error
  has_many :cash_drawer_sessions, dependent: :restrict_with_error
  has_many :outgoing_transfers, class_name: "TreasuryTransfer", foreign_key: :from_treasury_id, dependent: :restrict_with_error
  has_many :incoming_transfers, class_name: "TreasuryTransfer", foreign_key: :to_treasury_id, dependent: :restrict_with_error
  belongs_to :supplier, optional: true

  include MoneyInputs

  monetize :balance_cents
  monetize :opening_balance_cents

  money_input :opening_balance_cents

  validates :name, presence: true, uniqueness: { scope: :company_id }
  validates :treasury_type, presence: true, inclusion: { in: TYPES }

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position, :name) }
  scope :cash_drawers, -> { where(treasury_type: "cash_drawer") }
  # Exclude supplier AP ledgers from normal cash-flow selections
  scope :payable, -> { where.not(treasury_type: "supplier_ap") }
  scope :supplier_ap, -> { where(treasury_type: "supplier_ap") }

  def self.default_treasury
    active.find_by(is_default: true) || active.ordered.first
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[name treasury_type active is_default position balance_cents]
  end

  def self.ransackable_associations(_auth_object = nil)
    []
  end

  def apply_balance_delta!(delta_cents)
    update!(balance_cents: balance_cents + delta_cents)
  end
end