# frozen_string_literal: true

class CustomerAddress < ApplicationRecord
  belongs_to :customer

  validates :address, presence: true
  validates :label, length: { maximum: 50 }, allow_blank: true

  scope :ordered, -> { order(is_default: :desc, position: :asc, created_at: :asc) }

  before_validation :mark_first_as_default, on: :create
  before_save :clear_other_defaults, if: :is_default?

  def display_label
    parts = []
    parts << label if label.present?
    parts << address.truncate(60)
    parts.join(" — ")
  end

  private

  def mark_first_as_default
    return if is_default?
    return unless customer

    others = customer.addresses.reject { |a| a == self || a.marked_for_destruction? }
    self.is_default = true if others.empty?
  end

  def clear_other_defaults
    customer.addresses.where.not(id: id).update_all(is_default: false)
  end
end
