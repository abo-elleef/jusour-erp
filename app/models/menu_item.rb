# frozen_string_literal: true

class MenuItem < ApplicationRecord
  include Taxable
  include Tenantable
  include MenuItemImageVariants
  include MoneyInputs

  money_input :base_price_cents

  belongs_to :category
  has_many :location_menu_items, dependent: :destroy
  has_many :locations, through: :location_menu_items
  has_many :menu_item_modifier_groups, -> { order(:position) }, dependent: :destroy
  has_many :modifier_groups, through: :menu_item_modifier_groups
  has_many :modifiers, through: :modifier_groups
  has_many :order_items, dependent: :restrict_with_error
  has_many :combo_items, dependent: :restrict_with_error
  has_many :recipes, dependent: :destroy
  has_many :menu_promos, dependent: :destroy
  has_many :recipe_ingredients, through: :recipes, source: :ingredient
  has_many :printer_menu_items, dependent: :destroy
  has_many :printers, through: :printer_menu_items

  monetize :base_price_cents

  before_validation :assign_code, on: :create

  validates :name, presence: true
  validates :base_price_cents, numericality: { greater_than_or_equal_to: 0 }
  validates :tax_category, presence: true, inclusion: { in: TAX_CATEGORIES }
  validates :code, presence: true, uniqueness: { scope: :company_id, case_sensitive: false }

  # Next auto code for an item in `category`: "<CATEGORY_CODE>-NNN", where NNN is
  # the highest existing sequence for that prefix + 1. Custom codes that don't
  # match the "<prefix>-digits" shape are ignored so they never collide.
  def self.next_code(category)
    prefix = category.code.to_s
    max = unscoped_by_company.where(company_id: category.company_id)
      .where("code ~ ?", "^#{prefix}-[0-9]+$")
      .maximum(Arel.sql("CAST(SUBSTRING(code FROM #{prefix.length + 2}) AS INTEGER)"))
    "#{prefix}-#{((max || 0) + 1).to_s.rjust(3, '0')}"
  end

  scope :available, -> { where(available: true) }
  scope :ordered, -> { order(:position, :name) }
  scope :available_at_location, lambda { |location|
    return none if location.blank?

    available
      .joins(:location_menu_items)
      .where(location_menu_items: { location_id: location.id, available: true })
      .distinct
  }

  def available_at_location?(location)
    return available? if location.blank?

    available? && enabled_at_branch?(location)
  end

  def enabled_at_branch?(location)
    return false if location.blank?

    location_menu_items.any? { |row| row.location_id == location.id && row.available? }
  end

  def price_cents_at(location)
    return base_price_cents if location.blank?

    lmi = location_menu_items.find { |row| row.location_id == location.id }
    lmi&.effective_price_cents || base_price_cents
  end

  def modifier_group_ids
    menu_item_modifier_groups.map(&:modifier_group_id)
  end

  private

  def assign_company
    self.company ||= category&.company || Current.company
  end

  def assign_code
    self.code = self.class.next_code(category) if code.blank? && category
  end
end
