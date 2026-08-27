# frozen_string_literal: true

class Company < ApplicationRecord
  # Industry profiles. The profile drives which modules are on by default.
  BUSINESS_TYPES = %w[restaurant distribution].freeze

  # Toggleable modules. A feature is ON unless the company's profile turns it off
  # (see PROFILE_FEATURE_DEFAULTS) or a per-company override says otherwise.
  FEATURES = %w[manufacturing attendance kds menu ar_credit_sales price_tiers landed_cost].freeze

  # Per-profile default state. Anything not listed defaults to ON.
  PROFILE_FEATURE_DEFAULTS = {
    "restaurant"   => { "ar_credit_sales" => false, "price_tiers" => false, "landed_cost" => false },
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
  has_associated_audits

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true, format: { with: /\A[a-z0-9\-]+\z/ }
  validates :timezone, :currency, :locale, presence: true
  validates :business_type, inclusion: { in: BUSINESS_TYPES }

  after_create :seed_default_units
  after_create :seed_default_attendance_statuses
  after_create :seed_default_roles

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
