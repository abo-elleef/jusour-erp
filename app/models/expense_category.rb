# frozen_string_literal: true

class ExpenseCategory < ApplicationRecord
  include Tenantable

  CATEGORY_TYPES = %w[cogs labor rent utilities marketing maintenance other].freeze

  has_many :expenses, dependent: :restrict_with_error
  has_many :budgets, dependent: :destroy

  validates :name, presence: true, uniqueness: { scope: :company_id }
  validates :category_type, presence: true, inclusion: { in: CATEGORY_TYPES }

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

  def prevent_system_managed_destroy
    return unless system_managed?

    throw(:abort)
  end
end
