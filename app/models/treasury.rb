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
  has_many :assigned_users, class_name: "User", foreign_key: :assigned_treasury_id,
    dependent: :restrict_with_error, inverse_of: :assigned_treasury
  has_many :outgoing_transfers, class_name: "TreasuryTransfer", foreign_key: :from_treasury_id, dependent: :restrict_with_error
  has_many :incoming_transfers, class_name: "TreasuryTransfer", foreign_key: :to_treasury_id, dependent: :restrict_with_error
  belongs_to :supplier, optional: true

  include MoneyInputs

  monetize :balance_cents
  monetize :opening_balance_cents

  money_input :opening_balance_cents

  validates :name, presence: true, uniqueness: { scope: :company_id }
  validates :treasury_type, presence: true, inclusion: { in: TYPES }

  # Supplier AP ledgers are system-managed; never let their type be reassigned.
  before_update :lock_supplier_ap_type

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position, :name) }
  scope :cash_drawers, -> { where(treasury_type: "cash_drawer") }
  scope :safes, -> { where(treasury_type: %w[safe petty_cash]) }
  # Exclude supplier AP ledgers from normal cash-flow selections
  scope :payable, -> { where.not(treasury_type: "supplier_ap") }
  scope :supplier_ap, -> { where(treasury_type: "supplier_ap") }
  # Restricted (owner/manager-only) treasuries are hidden from everyone else.
  scope :visible_to, ->(user) { (user&.owner? || user&.manager?) ? all : where(restricted: false) }

  def self.default_treasury
    active.find_by(is_default: true) || active.ordered.first
  end

  def self.create_staff_drawer!(user_name:, company: nil)
    company ||= Current.company
    raise ArgumentError, "company is required" if company.blank?

    base_name = I18n.t("staff.form.drawer_name", name: user_name)
    name = base_name
    suffix = 2
    while unscoped.exists?(company_id: company.id, name: name)
      name = "#{base_name} (#{suffix})"
      suffix += 1
    end

    unscoped.create!(
      company: company,
      name: name,
      treasury_type: "cash_drawer",
      restricted: false,
      active: true,
      opening_balance_cents: 0,
      balance_cents: 0
    )
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[name treasury_type active is_default position balance_cents]
  end

  def self.ransackable_associations(_auth_object = nil)
    []
  end

  def supplier_ap?
    treasury_type == "supplier_ap"
  end

  def apply_balance_delta!(delta_cents)
    update!(balance_cents: balance_cents + delta_cents)
  end

  private

  def lock_supplier_ap_type
    self.treasury_type = treasury_type_was if treasury_type_changed? && treasury_type_was == "supplier_ap"
  end
end