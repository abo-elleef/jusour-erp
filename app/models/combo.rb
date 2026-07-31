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
  validate :ends_after_starts_when_scheduled

  scope :active, -> { where(active: true) }
  scope :scheduled_at, lambda { |at = Time.current|
    where("(starts_at IS NULL OR starts_at <= ?) AND (ends_at IS NULL OR ends_at >= ?)", at, at)
  }
  scope :available_at_location, lambda { |location, at: Time.current|
    return none if location.blank?

    unavailable_combo_ids = ComboItem
      .where.not(menu_item_id: MenuItem.available_at_location(location).select(:id))
      .select(:combo_id)

    active.scheduled_at(at).where.not(id: unavailable_combo_ids)
  }

  accepts_nested_attributes_for :combo_items, allow_destroy: true,
    reject_if: proc { |attrs| attrs["menu_item_id"].blank? }

  def highlighted_now?(at = Time.current)
    highlight? && active? && within_schedule?(at)
  end

  def within_schedule?(at = Time.current)
    (starts_at.nil? || starts_at <= at) && (ends_at.nil? || ends_at >= at)
  end

  private

  def ends_after_starts_when_scheduled
    return if starts_at.blank? || ends_at.blank?
    return if ends_at > starts_at

    errors.add(:ends_at, :must_be_after_starts)
  end
end
