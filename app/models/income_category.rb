# frozen_string_literal: true

class IncomeCategory < ApplicationRecord
  CATEGORY_TYPES = %w[sales catering services delivery other].freeze

  has_many :incomes, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: true
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
