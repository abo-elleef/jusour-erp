# frozen_string_literal: true

require "bcrypt"

class User < ApplicationRecord
  include Tenantable
  include MoneyInputs
  include Accountable

  audited associated_with: :company,
    except: %i[
      encrypted_password reset_password_token reset_password_sent_at
      remember_created_at pin_digest payroll_access_token
      payroll_pin_failed_attempts payroll_pin_locked_until
    ]

  money_input :monthly_salary_cents
  money_input :balance_deduction_cents

  ROLES = %w[owner super_manager manager sub_manager accountant cashier kitchen custom].freeze
  BUILTIN_ROLE_KEYS = %w[owner super_manager manager sub_manager accountant cashier kitchen].freeze
  INDEX_SORTABLE_COLUMNS = %w[name email role monthly_salary_cents created_at].freeze
  INDEX_DEFAULT_SORT = "name"
  INDEX_DEFAULT_SORT_DIRECTION = "asc"
  WORK_DAYS_PER_MONTH = 30
  WORK_HOURS_PER_MONTH = 300

  # Accountable — every employee's own current account. Finalizing a month
  # credits it with what they earned (the expense side goes to Salaries,
  # 5501); every voucher paid to them debits it, every voucher received from
  # them credits it, and staff meals debit it. A credit balance is what the
  # company still owes them; a debit balance is what they owe the company.
  # A liability block clear of tax payable (2100), loans (2101+), equipment
  # payable (2200) and accrued expenses (2300).
  WAGES_ACCOUNT_CODE_BASE = 2500

  devise :database_authenticatable, :recoverable, :rememberable

  validates :name, presence: true
  validates :role, presence: true, inclusion: { in: ROLES }
  validates :email, presence: true, if: :email_required?
  validates :email, uniqueness: { scope: :company_id, case_sensitive: false, allow_blank: true },
    if: :will_save_change_to_email?
  validates :email, format: { with: Devise.email_regexp, allow_blank: true }, if: :will_save_change_to_email?
  validates :password, presence: true, if: :password_required?
  validates :password, confirmation: true, if: :password_required?
  validates :password, length: { within: 6..128 }, allow_blank: true
  validates :payroll_access_token, presence: true, uniqueness: true
  validates :wages_account_code, presence: true, uniqueness: { scope: :company_id }
  validates :balance_deduction_cents, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true

  before_validation :assign_payroll_access_token, on: :create
  before_validation :assign_wages_account_code, on: :create
  before_validation :sync_hourly_rate_from_monthly_salary
  before_validation { self.balance_deduction_cents = nil unless balance_deduction_cents.to_i.positive? }

  scope :active, -> { where(active: true) }

  has_many :orders, dependent: :restrict_with_error
  has_many :stock_adjustments, dependent: :nullify
  has_many :manufacturing_runs, dependent: :nullify
  has_many :vendor_invoices, dependent: :nullify
  has_many :vendor_invoice_payments, dependent: :nullify
  has_many :stock_takes, dependent: :nullify
  has_many :notifications, as: :recipient, dependent: :destroy
  has_many :processed_payments, class_name: "Payment", foreign_key: :processed_by_user_id, dependent: :nullify
  has_many :shift_logs, dependent: :nullify
  has_many :cash_drawer_sessions, dependent: :nullify

  # Permission bundle (DB-backed). `role` string stays as the built-in identity
  # for the owner?/manager?/… predicates during the migration to permissions.
  belongs_to :assigned_role, class_name: "Role", foreign_key: :role_id,
    inverse_of: :users, optional: true
  belongs_to :assigned_treasury, class_name: "Treasury", optional: true

  validates :assigned_treasury, presence: true, on: :update
  before_create :ensure_assigned_treasury
  validate :assigned_treasury_must_be_valid_cash_drawer, if: -> { assigned_treasury.present? }

  # Location scope — the "where" axis of authorization (permissions are "what").
  # `all_locations` users operate company-wide; otherwise they're limited to
  # their assigned locations.
  has_many :user_locations, dependent: :destroy
  has_many :locations, through: :user_locations

  # Keep `role_id` (the permission source of truth) and the `role` string in
  # sync in both directions: forms pick a role_id → derive the string; seeds set
  # a string → link the matching built-in role so `can?` reads live DB perms.
  before_validation :reconcile_role
  has_many :expenses, dependent: :nullify
  has_many :incomes, dependent: :nullify
  has_many :payroll_adjustments, dependent: :destroy
  has_many :payroll_snapshots, dependent: :destroy
  # Money paid to or received from this employee. A voucher is a printed
  # document that moved cash, so the employee can't be deleted out from under
  # it — deactivate them instead.
  has_many :party_vouchers, class_name: "Voucher", as: :party, dependent: :restrict_with_error
  has_many :staff_attendances, dependent: :destroy
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

  def open_cash_drawer_session(location: nil)
    scope = cash_drawer_sessions.open
    scope = scope.where(location_id: location.id) if location
    scope.find_by(session_date: BusinessDay.today(location: location))
  end

  def todays_cash_drawer_session(location: nil)
    scope = cash_drawer_sessions
    scope = scope.where(location_id: location.id) if location
    scope.where(session_date: BusinessDay.today(location: location)).order(created_at: :desc).first
  end

  def shift_orders_time_range
    ranges = []

    # Active shift: clock-in to now
    if clocked_in?
      ranges << [current_shift.clocked_in_at, Time.current]
    end

    # Recently completed shift within the last 36 hours (covers overnight shifts)
    recent_completed = shift_logs.where.not(clocked_out_at: nil)
                                  .where(clocked_out_at: 36.hours.ago..)
                                  .order(clocked_in_at: :desc).first
    if recent_completed && !clocked_in?
      ranges << [recent_completed.clocked_in_at, recent_completed.clocked_out_at]
    end

    # Cash drawer sessions from the current or previous operating day (overnight
    # shifts open on a previous date)
    cash_drawer_sessions.where(session_date: [BusinessDay.today, BusinessDay.today - 1]).find_each do |drawer|
      end_time = drawer.status == "open" ? Time.current : drawer.updated_at
      ranges << [drawer.created_at, end_time]
    end

    if ranges.any?
      [ranges.map(&:first).min, ranges.map(&:last).max]
    else
      [BusinessDay.range(BusinessDay.today).begin, Time.current]
    end
  end

  def owner?
    role == "owner"
  end

  def manager?
    role == "manager"
  end

  def accountant?
    role == "accountant"
  end

  def cashier?
    role == "cashier"
  end

  def kitchen?
    role == "kitchen"
  end

  def sub_manager?
    role == "sub_manager"
  end

  def super_manager?
    role == "super_manager"
  end

  # Permission-based check — the way ALL new authorization should be written
  # (policies + views), instead of branching on role names.
  def can?(permission)
    return false if permission.blank?

    role_record = effective_role
    return role_record.can?(permission) if role_record

    # Last resort only if the company somehow has no matching DB role.
    Array(Permission::BUILTIN_ROLES.dig(role, :permissions)).include?(permission.to_s)
  end

  # The live DB Role driving this user's permissions: the explicitly assigned
  # role, or (for role_id-less users) the company's built-in role matching the
  # string role. Resolving from the DB — never a frozen code copy — is what makes
  # role edits in the UI take effect immediately for everyone.
  def effective_role
    return @effective_role if defined?(@effective_role)

    @effective_role = assigned_role ||
      (role.present? && company_id.present? ? Role.unscoped.find_by(company_id: company_id, key: role) : nil)
  end

  def reconcile_role
    return if company_id.blank?

    if will_save_change_to_role_id? && assigned_role
      self.role = assigned_role.built_in? && assigned_role.key.present? ? assigned_role.key : "custom"
    elsif role_id.blank? && role.present?
      match = Role.unscoped.find_by(company_id: company_id, key: role)
      self.role_id = match.id if match
    end
  end

  # Everyone except owners is paid from daily attendance. Owners keep a fixed
  # monthly salary even if attendance is logged for them.
  def attendance_paid?
    !owner?
  end

  # Effective permission keys for this user — the assigned role's, or (during
  # migration / for role_id-less users) the built-in defaults for the string role.
  def permission_keys
    effective_role&.permission_keys || Array(Permission::BUILTIN_ROLES.dig(role, :permissions))
  end

  # "Admin area" = holding any capability that isn't a pure operational-app
  # launch (POS/KDS/Production). Permission-based so new/custom roles route
  # correctly instead of falling through to an infinite redirect.
  ADMIN_PERMISSION_KEYS = (Permission::KEYS - %w[pos:access kitchen:access production:access]).freeze

  def admin_access?
    (permission_keys & ADMIN_PERMISSION_KEYS).any?
  end
  alias_method :can_access_admin?, :admin_access?

  def can_access_pos?
    can?("pos:access")
  end

  def can_access_kds?
    can?("kitchen:access")
  end

  def can_access_production?
    can?("production:access")
  end

  def can_manage_system?
    owner?
  end

  # The location ids this user may operate on — every active company location
  # when global, otherwise just their assigned set.
  def accessible_location_ids
    all_locations? ? Location.active.ids : location_ids
  end

  def can_access_location?(location)
    return true if all_locations?

    location_id = location.respond_to?(:id) ? location.id : location
    location_ids.include?(location_id)
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

  # The staff payroll link is opened with a 4-digit PIN, from any device. After
  # this many wrong guesses in a row the link is locked for a while, so the
  # 10,000 combinations can't be tried through it.
  PAYROLL_PIN_MAX_ATTEMPTS = 5
  PAYROLL_PIN_LOCKOUT = 15.minutes

  def payroll_pin_locked?
    payroll_pin_locked_until.present? && payroll_pin_locked_until.future?
  end

  # Checks a PIN typed on the payroll link, counting failures. A right PIN
  # clears the count; the fifth wrong one starts the lockout. While locked,
  # every PIN is refused without being checked.
  def verify_payroll_pin(raw)
    return false if payroll_pin_locked?

    if authenticate_pin(raw)
      update_columns(payroll_pin_failed_attempts: 0, payroll_pin_locked_until: nil) if payroll_pin_failed_attempts.positive?
      return true
    end

    attempts = payroll_pin_failed_attempts + 1
    if attempts >= PAYROLL_PIN_MAX_ATTEMPTS
      update_columns(payroll_pin_failed_attempts: 0, payroll_pin_locked_until: PAYROLL_PIN_LOCKOUT.from_now)
    else
      update_columns(payroll_pin_failed_attempts: attempts)
    end
    false
  end

  def deactivate!
    update!(active: false)
  end

  def activate!
    update!(active: true)
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

  # Accountable — see WAGES_ACCOUNT_CODE_BASE.
  def account_code = wages_account_code
  def account_name = "#{name} — حساب موظف"
  def account_type = "liability"
  def normal_balance = :credit

  # Positive: the company owes this employee. Negative: they owe the company
  # (paid ahead of what they've earned, or meals not yet covered by a salary).
  # as_of: the balance at the end of that day (vouchers post on their voucher
  # date, a month's accrual on its last day), so a past month isn't shown
  # with later months' advances and deductions.
  def staff_balance_cents(as_of: nil)
    lines = staff_account_lines
    lines = lines.where(journal_entries: { date: ..as_of.to_date }) if as_of
    lines.sum(:credit_cents) - lines.sum(:debit_cents)
  end

  # Vouchers to or from this employee for the month, newest first — see
  # Voucher.for_staff_month for where a late salary payout lands.
  def staff_vouchers_for_month(month)
    Voucher.for_staff_month(month).where(party_id: id)
           .includes(:treasury).order(voucher_date: :desc, created_at: :desc)
  end

  # The account at the end of the month, counting the month's own salary
  # payout even when it went out early next month — so a month paid on the
  # 3rd of the next shows as settled, the same as one paid on its last day.
  def staff_month_end_balance_cents(month)
    month = month.to_date.beginning_of_month
    late_payouts = Voucher.active.where(id: PayrollSnapshot.paid_late.for_month(month).where(user_id: id)
                                                           .select(:payout_voucher_id))
    staff_balance_cents(as_of: month.end_of_month) + late_payouts.sum(&:signed_amount_cents)
  end

  # Paid out less received back, for the month.
  def staff_paid_cents_for_month(month)
    staff_vouchers_for_month(month).sum(&:signed_amount_cents) * -1
  end

  # How far a payment can go before the "you are past the cap" warning: what
  # the company owes them now plus one month's salary, the same headroom the
  # old per-month advance limit gave.
  def staff_payment_headroom_cents
    staff_balance_cents + monthly_salary_cents.to_i
  end

  # Ledger lines on this employee's own account.
  def staff_account_lines
    JournalEntryLine.joins(:journal_entry)
                    .where(journal_entries: { company_id: company_id })
                    .where(account_code: wages_account_code)
  end

    private

  # Walks forward past any code a treasury already holds in this company —
  # supplier AP treasuries grow up from 2001 and per-type maxima are not
  # company-wide (see Treasury#assign_account_code).
  def assign_wages_account_code
    last = self.class.unscoped.where(company_id: company_id).maximum(:wages_account_code)
    candidate = [last.to_i, WAGES_ACCOUNT_CODE_BASE].max + 1
    candidate += 1 while Treasury.unscoped.where(company_id: company_id).exists?(account_code: candidate)
    self.wages_account_code = candidate
  end

  def ensure_assigned_treasury
    return if assigned_treasury_id.present? || assigned_treasury.present?
    return if name.blank?

    self.assigned_treasury = Treasury.create_staff_drawer!(
      user_name: name,
      company: company || Current.company
    )
  end

  def assigned_treasury_must_be_valid_cash_drawer
    treasury = assigned_treasury
    return if treasury.blank?

    unless treasury.treasury_type == "cash_drawer"
      errors.add(:assigned_treasury_id, :must_be_cash_drawer)
    end
    errors.add(:assigned_treasury_id, :must_be_active) unless treasury.active?
    errors.add(:assigned_treasury_id, :must_be_same_company) if treasury.company_id != company_id
  end

  def email_required?
    true
  end

  def password_required?
    !persisted? || password.present? || password_confirmation.present?
  end

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
