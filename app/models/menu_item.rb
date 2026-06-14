# frozen_string_literal: true

class MenuItem < ApplicationRecord
  include Taxable
  include Tenantable

  belongs_to :category
  has_many :location_menu_items, dependent: :destroy
  has_many :locations, through: :location_menu_items
  has_many :menu_item_modifier_groups, -> { order(:position) }, dependent: :destroy
  has_many :modifier_groups, through: :menu_item_modifier_groups
  has_many :modifiers, through: :modifier_groups
  has_many :combo_items, dependent: :restrict_with_error
  has_many :recipes, dependent: :destroy
  has_many :recipe_ingredients, through: :recipes, source: :ingredient
  has_one_attached :image
  has_many :printer_menu_items, dependent: :destroy
  has_many :printers, through: :printer_menu_items

  monetize :base_price_cents

  validates :name, presence: true
  validates :base_price_cents, numericality: { greater_than_or_equal_to: 0 }
  validates :tax_category, presence: true, inclusion: { in: TAX_CATEGORIES }

  scope :available, -> { where(available: true) }
  scope :ordered, -> { order(:position, :name) }

  def modifier_group_ids
    menu_item_modifier_groups.map(&:modifier_group_id)
  end

  private

  def assign_company
    self.company ||= category&.company || Current.company
  end
end
