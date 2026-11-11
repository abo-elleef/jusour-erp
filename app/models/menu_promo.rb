# frozen_string_literal: true

class MenuPromo < ApplicationRecord
  include Tenantable
  include MoneyInputs

  money_input :promo_price_cents

  belongs_to :menu_item
  belongs_to :location, optional: true
  # Optional: the promo applies only when this choice is on the line (e.g. the
  # "Double" size). Blank means it applies whatever was chosen.
  belongs_to :modifier, optional: true
  has_many :order_discounts, dependent: :nullify

  monetize :promo_price_cents

  validates :name, presence: true
  validates :promo_price_cents, numericality: { greater_than_or_equal_to: 0 }
  validates :starts_at, :ends_at, presence: true
  validate :ends_after_starts
  validate :modifier_belongs_to_item
  validate :promo_below_list_price

  scope :active, -> { where(active: true) }
  scope :active_at, lambda { |at = Time.current|
    active.where("starts_at <= ? AND ends_at >= ?", at, at)
  }
  scope :for_location, lambda { |location|
    return none if location.blank?

    where(location_id: [nil, location.id])
  }
  scope :ordered, -> { order(starts_at: :desc, name: :asc) }

  def active_now?(at = Time.current)
    active? && starts_at <= at && ends_at >= at
  end

  # The price the promo replaces: the item's price at the branch plus the
  # targeted choice's adjustment, so "Double for 150" is measured against the
  # Double's own price.
  def list_price_cents_at(location)
    base = location.present? ? menu_item.price_cents_at(location) : menu_item.base_price_cents
    base + modifier_adjustment_cents
  end

  def markdown_cents_at(location)
    [list_price_cents_at(location) - promo_price_cents, 0].max
  end

  def modifier_adjustment_cents
    modifier&.price_adjustment_cents.to_i
  end

  private

  def ends_after_starts
    return if starts_at.blank? || ends_at.blank?
    return if ends_at > starts_at

    errors.add(:ends_at, :must_be_after_starts)
  end

  def modifier_belongs_to_item
    return if modifier.blank? || menu_item.blank?
    return if menu_item.modifier_group_ids.include?(modifier.modifier_group_id)

    errors.add(:modifier_id, :not_on_item)
  end

  def promo_below_list_price
    return if menu_item.blank? || promo_price_cents.blank?
    return if promo_price_cents < list_price_cents_at(location)

    errors.add(:promo_price_cents, :must_be_below_list)
  end

  def assign_company
    self.company ||= menu_item&.company || Current.company
  end
end
