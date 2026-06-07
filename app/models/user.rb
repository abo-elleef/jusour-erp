# frozen_string_literal: true

require "bcrypt"

class User < ApplicationRecord
  ROLES = %w[owner manager cashier kitchen].freeze
  WORK_DAYS_PER_MONTH = 30
  WORK_HOURS_PER_MONTH = 300

  devise :database_authenticatable, :recoverable, :rememberable, :validatable

  validates :name, presence: true
  validates :role, presence: true, inclusion: { in: ROLES }
  validates :payroll_access_token, presence: true, uniqueness: true

  before_validation :assign_payroll_access_token, on: :create
  before_validation :sync_hourly_rate_from_monthly_salary

  scope :active, -> { where(active: true) }

  has_many :orders, dependent: :restrict_with_error
  has_many :stock_adjustments, dependent: :nullify
  has_many :purchase_orders, dependent: :nullify
  has_many :stock_takes, dependent: :nullify
  has_many :notifications, as: :recipient, dependent: :destroy
  has_many :processed_payments, class_name: "Payment", foreign_key: :processed_by_user_id, dependent: :nullify
  has_many :shift_logs, dependent: :nullify
  has_many :cash_drawer_sessions, dependent: :nullify
  has_many :expenses, dependent: :nullify
  has_many :incomes, dependent: :nullify
  has_many :payroll_adjustments, dependent: :destroy
  has_many :recorded_payroll_adjustments, class_name: "PayrollAdjustment",
    foreign_key: :recorded_by_id, dependent: :nullify, inverse_of: :recorded_by

  monetize :hourly_rate_cents
  monetize :monthly_salary_cents

  def clocked_in?
    shift_logs.active.exists?
  end

  def current_shift
    shift_logs.active.order(clocked_in_at: :desc).first
  end

  def owner?
    role == "owner"
  end

  def manager?
    role == "manager"
  end

  def cashier?
    role == "cashier"
  end

  def kitchen?
    role == "kitchen"
  end

  def admin_access?
    owner? || manager?
  end

  def can_access_pos?
    owner? || manager? || cashier?
  end

  def can_access_kds?
    owner? || manager? || kitchen?
  end

  def can_access_admin?
    owner? || manager?
  end

  def can_manage_system?
    owner?
  end

  def pin=(raw)
    return if raw.blank?

    self.pin_digest = BCrypt::Password.create(raw.to_s)
  end

  def authenticate_pin(raw)
    return false if pin_digest.blank?

    BCrypt::Password.new(pin_digest) == raw.to_s
  rescue BCrypt::Errors::InvalidHash
    false
  end

  def pin_configured?
    pin_digest.present?
  end

  def deactivate!
    update!(active: false)
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[name email role active created_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    []
  end

  def self.ransackable_scopes(_auth_object = nil)
    %w[name_or_email_cont]
  end

  scope :name_or_email_cont, lambda { |value|
    term = value.to_s.strip
    return all if term.blank?

    pattern = "%#{sanitize_sql_like(term)}%"
    where("users.name ILIKE :p OR users.email ILIKE :p", p: pattern)
  }

  def role_label
    I18n.t("user.roles.#{role}", default: role.to_s.humanize)
  end

  def daily_rate_cents
    return 0 if monthly_salary_cents.to_i.zero?

    (monthly_salary_cents.to_f / WORK_DAYS_PER_MONTH).round
  end

  def monthly_payroll(payroll_month = Date.current, sort: nil, direction: nil)
    Accounting::MonthlyPayrollService.new(self, payroll_month, sort: sort, direction: direction).call
  end

  private

  def assign_payroll_access_token
    self.payroll_access_token ||= SecureRandom.urlsafe_base64(24)
  end

  def sync_hourly_rate_from_monthly_salary
    self.hourly_rate_cents = if monthly_salary_cents.to_i.zero?
                               0
                             else
                               (monthly_salary_cents.to_f / WORK_HOURS_PER_MONTH).round
                             end
  end
end
