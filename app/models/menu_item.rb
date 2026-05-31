# frozen_string_literal: true

class MenuItem < ApplicationRecord
  include Taxable

  belongs_to :category
  has_many :modifier_groups, dependent: :destroy
  has_many :modifiers, through: :modifier_groups
  has_many :combo_items, dependent: :restrict_with_error
  has_many :recipes, dependent: :destroy
  has_many :recipe_ingredients, through: :recipes, source: :ingredient
  has_one_attached :image

  monetize :base_price_cents

  validates :name, presence: true
  validates :base_price_cents, numericality: { greater_than_or_equal_to: 0 }
  validates :tax_category, presence: true, inclusion: { in: TAX_CATEGORIES }

  scope :available, -> { where(available: true) }
  scope :ordered, -> { order(:position, :name) }

  accepts_nested_attributes_for :modifier_groups, allow_destroy: true,
    reject_if: proc { |attrs| attrs["name"].blank? }
end
