# frozen_string_literal: true

class IngredientCategory < ApplicationRecord
  has_many :ingredients, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: true

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position, :name) }
end
