# frozen_string_literal: true

# A cash register / POS machine at a branch, bound to a receipt printer.
# Cashiers select the workstation once on that machine so receipt jobs print
# locally without rewriting shared printer settings.
class Workstation < ApplicationRecord
  include Tenantable

  belongs_to :company
  belongs_to :location
  belongs_to :receipt_printer, class_name: "Printer", optional: true
  has_many :orders, dependent: :nullify

  validates :name, presence: true, uniqueness: { scope: :location_id }
  validate :location_must_be_branch
  validate :receipt_printer_must_match_location

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:name) }
  scope :for_location, lambda { |location|
    where(location_id: location.is_a?(Location) ? location.id : location)
  }

  def self.ransackable_attributes(_auth_object = nil)
    %w[name active location_id created_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[location receipt_printer]
  end

  private

  def location_must_be_branch
    return if location.blank? || location.branch?

    errors.add(:location, :must_be_branch)
  end

  def receipt_printer_must_match_location
    return if receipt_printer.blank?
    return if receipt_printer.location_id == location_id && receipt_printer.printer_type == "receipt"

    errors.add(:receipt_printer, :must_be_receipt_at_branch)
  end
end
