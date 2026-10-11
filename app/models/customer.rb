# frozen_string_literal: true

class Customer < ApplicationRecord
  include Tenantable
  include MoneyInputs
  include Accountable

  INDEX_SORTABLE_COLUMNS = %w[name phone loyalty_points total_spent_cents created_at].freeze
  INDEX_DEFAULT_SORT = "created_at"
  INDEX_DEFAULT_SORT_DIRECTION = "desc"

  # regular = the everyday customer (a "doctor" in dental terms; cash/immediate);
  # commercial = a credit client with negotiated pricing and an AR balance.
  CUSTOMER_TYPES = %w[regular commercial].freeze

  has_many :orders, dependent: :nullify
  has_many :loyalty_transactions, dependent: :destroy
  # SPIKE (AR): the customer's Accounts-Receivable ledger treasury. Its balance is
  # the amount this customer currently owes us. Created lazily on first credit sale
  # (mirrors Supplier#ap_treasury), so ordinary POS customers never get one.
  belongs_to :ar_treasury, class_name: "Treasury", foreign_key: :treasury_id, optional: true
  belongs_to :price_tier, optional: true
  has_many :customer_invoices, dependent: :restrict_with_error
  has_many :addresses, class_name: "CustomerAddress", dependent: :destroy, inverse_of: :customer

  accepts_nested_attributes_for :addresses, allow_destroy: true,
    reject_if: proc { |attrs| attrs["address"].to_s.strip.blank? }

  before_validation :normalize_contact_fields

  validates :customer_type, inclusion: { in: CUSTOMER_TYPES }
  validates :discount_override_percent,
    numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }, allow_nil: true
  validates :credit_warning_limit_cents, :credit_hard_limit_cents,
    numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :credit_terms_days, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :email, uniqueness: { scope: :company_id }, allow_blank: true
  validates :phone, uniqueness: { scope: :company_id }, allow_blank: true
  validates :phone_secondary, uniqueness: { scope: :company_id }, allow_blank: true
  validate :email_or_phone_present
  validate :phones_must_differ
  validate :phones_unique_across_columns

  monetize :total_spent_cents, allow_nil: false
  money_input :credit_warning_limit_cents, :credit_hard_limit_cents

  def self.ransackable_attributes(_auth_object = nil)
    %w[name email phone phone_secondary loyalty_points total_spent_cents created_at updated_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[addresses]
  end

  def display_name
    name.presence || phone.presence || phone_secondary.presence || email.presence || "Customer"
  end

  # Amount this customer currently owes us (0 when they have no AR ledger).
  def ar_balance_cents
    ar_treasury&.balance_cents || 0
  end

  # Accountable — see Supplier#to_account: a customer's account is its AR
  # treasury's, not its own.
  def to_account
    ar_treasury&.to_account
  end

  def commercial?
    customer_type == "commercial"
  end

  # The discount % applied to this customer's sale lines: a per-customer override
  # wins over their tier; neither set means no discount.
  def effective_discount_percent
    return discount_override_percent if discount_override_percent.present?

    price_tier&.discount_percent || 0
  end

  # Credit standing for a prospective AR balance (e.g. after adding a new invoice):
  #   :blocked  — at/over the hard limit (sale must be refused)
  #   :warning  — at/over the soft warning limit (allowed, but flag it)
  #   :ok       — within limits (or no limits configured)
  def credit_status_for(prospective_balance_cents)
    if credit_hard_limit_cents.present? && prospective_balance_cents > credit_hard_limit_cents
      :blocked
    elsif credit_warning_limit_cents.present? && prospective_balance_cents > credit_warning_limit_cents
      :warning
    else
      :ok
    end
  end

  def default_address
    addresses.find_by(is_default: true) || addresses.ordered.first
  end

  def contact_phones
    [phone, phone_secondary].compact_blank
  end

  # Catch DB unique-index races (and any validation misses) as model errors
  # instead of bubbling ActiveRecord::RecordNotUnique as a 500.
  def save(**options, &block)
    super
  rescue ActiveRecord::RecordNotUnique => error
    recover_from_unique_violation(error)
    false
  end

  def save!(**options, &block)
    save(**options, &block) || raise(ActiveRecord::RecordInvalid, self)
  end

  private

  def normalize_contact_fields
    self.name = name.to_s.strip.presence
    self.email = email.to_s.strip.presence
    self.phone = phone.to_s.strip.presence
    self.phone_secondary = phone_secondary.to_s.strip.presence
  end

  def email_or_phone_present
    return if email.present? || phone.present?

    errors.add(:base, I18n.t("customers.errors.email_or_phone_required"))
  end

  def phones_must_differ
    return if phone.blank? || phone_secondary.blank?
    return unless phone == phone_secondary

    errors.add(:phone_secondary, I18n.t("customers.errors.phones_must_differ"))
  end

  def phones_unique_across_columns
    return if company_id.blank?

    scope = self.class.unscoped_by_company.where(company_id: company_id)
    scope = scope.where.not(id: id) if persisted?

    if phone.present? && scope.where(phone_secondary: phone).exists?
      errors.add(:phone, I18n.t("customers.errors.phone_taken"))
    end

    if phone_secondary.present? && scope.where(phone: phone_secondary).exists?
      errors.add(:phone_secondary, I18n.t("customers.errors.phone_taken"))
    end
  end

  def recover_from_unique_violation(error)
    message = error.message.to_s
    if message.match?(/phone_secondary/i)
      errors.add(:phone_secondary, I18n.t("customers.errors.phone_taken"))
    elsif message.match?(/phone/i)
      errors.add(:phone, I18n.t("customers.errors.phone_taken"))
    elsif message.match?(/email/i)
      errors.add(:email, I18n.t("customers.errors.email_taken"))
    else
      errors.add(:base, I18n.t("customers.errors.contact_taken"))
    end
  end
end
