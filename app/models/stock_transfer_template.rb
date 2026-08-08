# frozen_string_literal: true

class StockTransferTemplate < ApplicationRecord
  include Tenantable

  belongs_to :default_from_location, class_name: "Location", optional: true
  belongs_to :default_to_location, class_name: "Location", optional: true
  has_many :stock_transfer_template_lines, -> { order(:position, :created_at) },
           dependent: :destroy, inverse_of: :stock_transfer_template
  has_many :ingredients, through: :stock_transfer_template_lines

  accepts_nested_attributes_for :stock_transfer_template_lines,
    allow_destroy: true,
    reject_if: proc { |attrs| attrs["ingredient_id"].blank? }

  validates :name, presence: true, uniqueness: { scope: :company_id }
  validate :must_have_lines, if: :active?
  validate :default_locations_must_differ
  validate :default_locations_must_be_active

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position, :name) }

  def self.ransackable_attributes(_auth_object = nil)
    %w[name active position]
  end

  private

  def must_have_lines
    return if stock_transfer_template_lines.reject(&:marked_for_destruction?).any?

    errors.add(:base, :needs_lines)
  end

  def default_locations_must_differ
    return if default_from_location_id.blank? || default_to_location_id.blank?
    return unless default_from_location_id == default_to_location_id

    errors.add(:default_to_location_id, :same_as_source)
  end

  def default_locations_must_be_active
    errors.add(:default_from_location_id, :inactive) if default_from_location && !default_from_location.active?
    errors.add(:default_to_location_id, :inactive) if default_to_location && !default_to_location.active?
  end
end
