# frozen_string_literal: true

class Location < ApplicationRecord
  include Tenantable
  include HasReceiptLogo

  TYPES = %w[central_kitchen branch].freeze

  belongs_to :company
  # Where this branch's drawers are banked when a shift closes. Set by an admin,
  # not chosen at the till — see #deposit_treasury_or_default.
  belongs_to :deposit_treasury, class_name: "Treasury", optional: true
  # A drawer's over/short at close (see Accounting::DrawerVarianceDocuments).
  # Overage: an Income in this category, into this treasury — the drawer's own
  # deposit safe when blank. Shortage waived by a manager: an Expense in this
  # category. Both categories are created on first use when blank, so closing a
  # drawer never waits on a setting.
  belongs_to :cash_over_treasury, class_name: "Treasury", optional: true
  belongs_to :cash_over_income_category, class_name: "IncomeCategory", optional: true
  belongs_to :cash_short_expense_category, class_name: "ExpenseCategory", optional: true
  has_many :ingredient_locations, dependent: :destroy
  has_many :ingredients, through: :ingredient_locations
  has_many :location_menu_items, dependent: :destroy
  has_many :menu_items, through: :location_menu_items
  has_many :menu_promos, dependent: :nullify
  has_many :stock_batches, dependent: :nullify
  has_many :stock_adjustments, dependent: :nullify
  has_many :stock_takes, dependent: :nullify
  has_many :manufacturing_runs, dependent: :nullify
  has_many :orders, dependent: :nullify
  has_many :vendor_invoices, dependent: :restrict_with_error
  has_many :printers, dependent: :restrict_with_error
  has_many :cash_drawer_sessions, dependent: :nullify
  has_many :workstations, dependent: :destroy
  has_many :location_operating_days, dependent: :destroy
  has_many :outgoing_stock_transfers, class_name: "StockTransfer", foreign_key: :from_location_id, dependent: :restrict_with_error
  has_many :incoming_stock_transfers, class_name: "StockTransfer", foreign_key: :to_location_id, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: { scope: :company_id }
  validates :slug, presence: true, uniqueness: { scope: :company_id },
    format: { with: /\A[a-z0-9\-]+\z/ }
  validates :location_type, presence: true, inclusion: { in: TYPES }
  validates :business_day_start_hour,
            numericality: { only_integer: true, in: 0..23, allow_nil: true }
  validates :table_count, numericality: { only_integer: true, in: 1..200, allow_nil: true }
  validates :table_count, presence: true, if: :table_service?
  validates :business_day_mode, inclusion: { in: BusinessDay::MODES }
  validate :edit_orders_pin_is_four_digits

  before_validation :generate_slug, if: -> { slug.blank? && name.present? }
  before_validation :normalize_business_day_start_hour
  before_validation :normalize_business_day_mode

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position, :name) }
  scope :branches, -> { where(location_type: "branch") }
  scope :central_kitchens, -> { where(location_type: "central_kitchen") }
  scope :public_menu_enabled, -> { where(public_menu_enabled: true) }
  scope :publicly_accessible, -> { active.branches.public_menu_enabled }
  scope :default_production, -> { where(default_production_location: true) }

  before_validation :clear_public_menu_for_non_branches
  before_validation :clear_business_day_settings_for_non_branches
  before_validation :clear_default_production_for_non_central_kitchens
  before_save :unset_other_default_production_locations, if: -> { default_production_location? && active? }

  def self.ransackable_attributes(_auth_object = nil)
    %w[name location_type active]
  end

  # One PIN per branch unlocks a placed order for changes at the register. Shared by
  # whoever runs the floor, so it is checked against the branch, not a person; the
  # audit log records which signed-in user typed it.
  EDIT_ORDERS_PIN_MAX_ATTEMPTS = 5
  EDIT_ORDERS_PIN_LOCKOUT = 5.minutes

  # Write-only: the form field always comes back empty.
  attr_reader :edit_orders_pin

  def edit_orders_pin=(raw)
    return if raw.blank?

    @edit_orders_pin_raw = raw
    self.edit_orders_pin_digest = BCrypt::Password.create(raw.to_s)
  end

  def edit_orders_pin_configured?
    edit_orders_pin_digest.present?
  end

  def edit_orders_pin_locked?
    edit_orders_pin_locked_until.present? && edit_orders_pin_locked_until.future?
  end

  # Counts failures like the payroll PIN: the fifth wrong one locks the PIN for a
  # few minutes, during which every PIN is refused without being checked.
  def verify_edit_orders_pin(raw)
    return false unless edit_orders_pin_configured?
    return false if edit_orders_pin_locked?

    if edit_orders_pin_matches?(raw)
      update_columns(edit_orders_pin_failed_attempts: 0, edit_orders_pin_locked_until: nil) if edit_orders_pin_failed_attempts.positive?
      return true
    end

    attempts = edit_orders_pin_failed_attempts + 1
    if attempts >= EDIT_ORDERS_PIN_MAX_ATTEMPTS
      update_columns(edit_orders_pin_failed_attempts: 0, edit_orders_pin_locked_until: EDIT_ORDERS_PIN_LOCKOUT.from_now)
    else
      update_columns(edit_orders_pin_failed_attempts: attempts)
    end
    false
  end

  # The central kitchen production forms should default to. Falls back to the
  # first active central kitchen (by display order) when none is flagged.
  def self.default_production_location
    active.central_kitchens.default_production.ordered.first || active.central_kitchens.ordered.first
  end

  def central_kitchen?
    location_type == "central_kitchen"
  end

  def branch?
    location_type == "branch"
  end

  def effective_business_day_start_hour
    BusinessDay.start_hour(location: self)
  end

  def business_day_start_hour_overridden?
    business_day_start_hour.present?
  end

  def manual_business_day?
    BusinessDay.manual?(location: self)
  end

  def automatic_business_day?
    BusinessDay.automatic?(location: self)
  end

  def ingredient_stock(ingredient)
    ingredient_locations.find_by(ingredient: ingredient)
  end

  def phone_url
    sanitized = phone.to_s.gsub(/[^\d+]/, "")
    return if sanitized.blank?

    "tel:#{sanitized}"
  end

  def whatsapp_url
    digits = whatsapp_number.to_s.gsub(/\D/, "")
    return if digits.blank?

    "https://wa.me/#{digits}"
  end

  # The branch's own treasury when an admin has named one, otherwise the company
  # default so the cash still lands somewhere traceable. Callers should warn when
  # they end up on the fallback — see #deposit_treasury_configured?.
  def deposit_treasury_or_default
    deposit_treasury || Treasury.default_treasury
  end

  # The categories a drawer's over/short is booked to. Created on first use and
  # remembered on the branch, so a cashier closing at midnight is never stopped
  # by a setting nobody filled in. One shared category per company by name, so
  # several branches don't each grow their own copy.
  def cash_over_income_category!
    cash_over_income_category || remember!(:cash_over_income_category,
      IncomeCategory.find_or_create_by!(company: company,
                                        name: I18n.t("accounting.cash_drawer.variance_docs.over_category", locale: I18n.default_locale)) do |c|
        c.category_type = "other"
      end)
  end

  def cash_short_expense_category!
    cash_short_expense_category || remember!(:cash_short_expense_category,
      ExpenseCategory.find_or_create_by!(company: company,
                                         name: I18n.t("accounting.cash_drawer.variance_docs.short_category", locale: I18n.default_locale)) do |c|
        c.category_type = "other"
      end)
  end

  def deposit_treasury_configured?
    deposit_treasury_id.present?
  end

  private

  def edit_orders_pin_is_four_digits
    return if @edit_orders_pin_raw.blank?

    errors.add(:edit_orders_pin, :invalid) unless @edit_orders_pin_raw.to_s.match?(/\A\d{4}\z/)
  end

  def edit_orders_pin_matches?(raw)
    BCrypt::Password.new(edit_orders_pin_digest) == raw.to_s
  rescue BCrypt::Errors::InvalidHash
    false
  end

  def clear_public_menu_for_non_branches
    self.public_menu_enabled = false unless branch?
  end

  def clear_business_day_settings_for_non_branches
    return if branch?

    self.business_day_start_hour = nil
    self.business_day_mode = BusinessDay::DEFAULT_MODE
  end

  def clear_default_production_for_non_central_kitchens
    self.default_production_location = false unless central_kitchen?
  end

  def unset_other_default_production_locations
    Location.where(default_production_location: true)
      .where.not(id: id)
      .update_all(default_production_location: false)
  end

  def normalize_business_day_start_hour
    self.business_day_start_hour = nil if business_day_start_hour.blank?
  end

  def normalize_business_day_mode
    self.business_day_mode = BusinessDay::DEFAULT_MODE if business_day_mode.blank?
  end

  def generate_slug
    base = name.to_s.parameterize.presence || "location"
    candidate = base
    counter = 1
    scope = Location.unscoped.where(company_id: company_id).where.not(id: id)
    while scope.exists?(slug: candidate)
      candidate = "#{base}-#{counter}"
      counter += 1
    end
    self.slug = candidate
  end

  def assign_company
    self.company ||= Current.company
  end

  def remember!(association, record)
    update_column(:"#{association}_id", record.id)
    association(association).target = record
    record
  end
end
