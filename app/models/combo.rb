# frozen_string_literal: true

class Combo < ApplicationRecord
  include Tenantable
  include MoneyInputs

  money_input :price_cents

  has_many :combo_items, dependent: :destroy
  has_many :menu_items, through: :combo_items

  monetize :price_cents

  validates :name, presence: true
  validates :price_cents, numericality: { greater_than_or_equal_to: 0 }

  scope :active, -> { where(active: true) }
  scope :available_at_location, lambda { |location|
    return none if location.blank?

    unavailable_combo_ids = ComboItem
      .where.not(menu_item_id: MenuItem.available_at_location(location).select(:id))
      .select(:combo_id)

    active.where.not(id: unavailable_combo_ids)
  }

  accepts_nested_attributes_for :combo_items, allow_destroy: true,
    reject_if: proc { |attrs| attrs["menu_item_id"].blank? }
end
