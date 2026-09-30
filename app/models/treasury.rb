# frozen_string_literal: true

class Treasury < ApplicationRecord
  include Tenantable
  include Accountable

  TYPES = %w[cash_drawer bank safe petty_cash mobile_wallet other supplier_ap customer_ar].freeze

  # System-managed ledger treasuries that must not be picked as normal cash sources.
  LEDGER_TYPES = %w[supplier_ap customer_ar].freeze

  # Where each treasury_type's account codes start. Also read by
  # AccountListService, JournalEntriesController and ChartOfAccountsService —
  # though now that account_code is persisted, they mostly don't need to.
  TREASURY_TYPE_BASE = {
    "cash_drawer"   => 1000,
    "bank"          => 1100,
    "safe"          => 1200,
    "petty_cash"    => 1300,
    "mobile_wallet" => 1400,
    "other"         => 1500,
    "customer_ar"   => 1150,
    "supplier_ap"   => 2000
  }.freeze

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
  belongs_to :customer, optional: true

  include MoneyInputs

  monetize :balance_cents
  monetize :opening_balance_cents

  money_input :opening_balance_cents

  validates :name, presence: true, uniqueness: { scope: :company_id }
  validates :treasury_type, presence: true, inclusion: { in: TYPES }
  validates :account_code, presence: true, uniqueness: { scope: :company_id }

  before_validation :assign_account_code, on: :create

  # Supplier AP ledgers are system-managed; never let their type be reassigned.
  before_update :lock_supplier_ap_type

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position, :name) }
  scope :cash_drawers, -> { where(treasury_type: "cash_drawer") }
  scope :safes, -> { where(treasury_type: %w[safe petty_cash]) }
  # Exclude system-managed ledger treasuries (AP/AR) from normal cash-flow selections
  scope :payable, -> { where.not(treasury_type: LEDGER_TYPES) }
  scope :supplier_ap, -> { where(treasury_type: "supplier_ap") }
  scope :customer_ar, -> { where(treasury_type: "customer_ar") }
  # Restricted (owner/manager-only) treasuries are hidden from everyone else.
  scope :visible_to, ->(user) { (user&.owner? || user&.manager?) ? all : where(restricted: false) }

  def self.default_treasury
    active.find_by(is_default: true) || active.ordered.first
  end

  # The treasury a cashier carries their opening float out of. A safe is the usual
  # home for it; fall back to the company default so opening a drawer never fails
  # for want of a source.
  def self.float_source
    active.where(treasury_type: "safe").ordered.first || default_treasury
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

  # Accountable — account_code is a real, persisted column (like Loan/Partner/
  # *Category's), assigned once at creation and never recomputed. It used to be
  # derived live from base + sibling ordinal, which could silently shift for an
  # existing treasury if a new sibling was created ahead of it in sort order;
  # persisting it the same way the other Accountables already did removes that.
  def account_name = name

  def account_type
    treasury_type == "supplier_ap" ? "liability" : "asset"
  end

  def normal_balance
    account_type == "liability" ? :credit : :debit
  end

  def account_treasury_id = id

  private

  # Stable per-company-per-type account code, assigned once at creation and
  # never changed — same pattern as Loan/Partner/ExpenseCategory/IncomeCategory.
  def assign_account_code
    return if account_code.present?

    base = TREASURY_TYPE_BASE.fetch(treasury_type, 1500)
    last = self.class.unscoped.where(company_id: company_id, treasury_type: treasury_type)
                     .maximum(:account_code)
    self.account_code = (last || base) + 1
  end

  def lock_supplier_ap_type
    self.treasury_type = treasury_type_was if treasury_type_changed? && treasury_type_was == "supplier_ap"
  end
end