# frozen_string_literal: true

class Company < ApplicationRecord
  # Industry profiles. The profile drives which modules are on by default.
  BUSINESS_TYPES = %w[restaurant distribution].freeze

  # Toggleable modules. A feature is ON unless the company's profile turns it off
  # (see PROFILE_FEATURE_DEFAULTS) or a per-company override says otherwise.
  # `menu` covers menu-based selling as a whole — the menu catalogue, the POS
  # tickets it produces, and the reports built on them (sales, food cost, usage,
  # tax). A distributor sells products from a price list, not dishes from a menu,
  # so all of it is off for them.
  # `storefront` is the public product-catalog website (see Storefront) — a
  # distributor's answer to the restaurant's per-branch public menu.
  FEATURES = %w[manufacturing attendance kds menu ar_credit_sales price_tiers landed_cost leads storefront].freeze

  # Per-profile default state. Anything not listed defaults to ON.
  PROFILE_FEATURE_DEFAULTS = {
    "restaurant"   => { "ar_credit_sales" => false, "price_tiers" => false, "landed_cost" => false, "leads" => false,
                        "storefront" => false },
    "distribution" => { "manufacturing" => false, "attendance" => false, "kds" => false, "menu" => false }
  }.freeze

  has_many :users, dependent: :destroy
  has_many :locations, dependent: :destroy
  has_many :orders, dependent: :destroy
  has_many :units, dependent: :destroy
  has_many :attendance_statuses, dependent: :destroy
  has_many :staff_attendances, dependent: :destroy
  has_many :cash_drawer_sessions, dependent: :destroy
  has_many :customers, dependent: :destroy
  has_many :leads, dependent: :destroy
  has_one :storefront, dependent: :destroy
  has_one :company_setting
  has_associated_audits

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true, format: { with: /\A[a-z0-9\-]+\z/ }
  validates :timezone, :currency, :locale, presence: true
  validates :business_type, inclusion: { in: BUSINESS_TYPES }

  after_create :seed_default_units
  after_create :seed_default_attendance_statuses
  after_create :seed_default_roles

  # Subscription. `paid_until` NULL = no expiry (internal / demo / legacy).
  # After the date passes the company keeps working for a grace period, with
  # the owner nagged by a banner; after that sign-in is locked until renewed.
  SUBSCRIPTION_GRACE_DAYS = 7
  SUBSCRIPTION_WARNING_DAYS = 7

  # :suspended (switched off by us), :expired (past grace), :grace (past the
  # date, still working), :expiring (date within the warning window), :ok.
  def subscription_status(today = subscription_today)
    return :suspended unless active?
    return :ok if paid_until.nil?

    if today > paid_until + SUBSCRIPTION_GRACE_DAYS
      :expired
    elsif today > paid_until
      :grace
    elsif today >= paid_until - SUBSCRIPTION_WARNING_DAYS
      :expiring
    else
      :ok
    end
  end

  def access_blocked?
    %i[suspended expired].include?(subscription_status)
  end

  # Whole days until paid_until (negative once passed); nil when there is no expiry.
  def days_until_expiry(today = subscription_today)
    paid_until && (paid_until - today).to_i
  end

  # Last day of work before the lock, for the "grace" banner.
  def grace_ends_on
    paid_until && paid_until + SUBSCRIPTION_GRACE_DAYS
  end

  # Record a payment: extend from the later of today and the current expiry, so
  # renewing early never loses the days already paid for.
  def extend_subscription!(months:)
    base = [paid_until, subscription_today].compact.max
    update!(paid_until: base >> months)
  end

  # Names of units this company can use (built-in + custom, active only).
  def unit_names
    units.active.pluck(:name)
  end

  def restaurant?
    business_type == "restaurant"
  end

  def distribution?
    business_type == "distribution"
  end

  # The name printed on a receipt. The branch's own name when the slip belongs
  # to a branch, otherwise this company's name — never the product's.
  def receipt_name(location: nil)
    location&.name.presence || name
  end

  # Is a toggleable module on for this company? A per-company override wins;
  # otherwise the industry profile's default applies (ON unless it opts out).
  def feature_enabled?(feature)
    key = feature.to_s
    overrides = feature_overrides || {}
    return overrides[key] == true if overrides.key?(key)

    PROFILE_FEATURE_DEFAULTS.dig(business_type, key) != false
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[name slug active created_at]
  end

  private

  def subscription_today
    Time.find_zone(timezone)&.today || Date.current
  end

  def seed_default_units
    Unit.seed_defaults!(self)
  end

  def seed_default_attendance_statuses
    AttendanceStatus.seed_defaults!(self)
  end

  def seed_default_roles
    Roles::Seeder.call(self)
  end
end
