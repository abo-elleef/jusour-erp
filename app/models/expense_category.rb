# frozen_string_literal: true

class ExpenseCategory < ApplicationRecord
  include Tenantable

  CATEGORY_TYPES = %w[cogs labor rent utilities marketing maintenance other].freeze
  # Dynamic expense accounts occupy the 5001-5499 range; the first category is 5001.
  ACCOUNT_CODE_BASE = 5000

  has_many :expenses, dependent: :restrict_with_error
  has_many :budgets, dependent: :destroy

  validates :name, presence: true, uniqueness: { scope: :company_id }
  validates :category_type, presence: true, inclusion: { in: CATEGORY_TYPES }
  validates :account_code, presence: true, uniqueness: { scope: :company_id }

  before_validation :assign_account_code, on: :create

  scope :ordered, -> { order(:position, :name) }
  scope :manual, -> { where(system_managed: false) }

  def self.ransackable_attributes(_auth_object = nil)
    %w[name category_type position system_managed]
  end

  def self.ransackable_associations(_auth_object = nil)
    []
  end

  before_destroy :prevent_system_managed_destroy

  private

  # Stable per-company account code, assigned once at creation and never changed.
  def assign_account_code
    return if account_code.present?

    last = self.class.where(company_id: company_id).maximum(:account_code) || ACCOUNT_CODE_BASE
    self.account_code = last + 1
  end

  def prevent_system_managed_destroy
    return unless system_managed?

    throw(:abort)
  end
end
