# frozen_string_literal: true

class Treasury < ApplicationRecord
  TYPES = %w[cash_drawer bank safe petty_cash mobile_wallet other].freeze

  has_many :treasury_transactions, dependent: :destroy
  has_many :expenses, dependent: :restrict_with_error
  has_many :incomes, dependent: :restrict_with_error
  has_many :cash_drawer_sessions, dependent: :restrict_with_error

  monetize :balance_cents
  monetize :opening_balance_cents

  validates :name, presence: true, uniqueness: true
  validates :treasury_type, presence: true, inclusion: { in: TYPES }

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position, :name) }
  scope :cash_drawers, -> { where(treasury_type: "cash_drawer") }

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
