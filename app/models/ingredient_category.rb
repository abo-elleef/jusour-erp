# frozen_string_literal: true

class IngredientCategory < ApplicationRecord
  include Tenantable

  has_many :ingredients, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: { scope: :company_id }

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position, :name) }

  def self.ransackable_attributes(_auth_object = nil)
    %w[name active position]
  end

  def self.ransackable_associations(_auth_object = nil)
    []
  end
end
