# frozen_string_literal: true

class LocationOperatingDay < ApplicationRecord
  include Tenantable

  belongs_to :company
  belongs_to :location
  belongs_to :opened_by, class_name: "User", optional: true
  belongs_to :closed_by, class_name: "User", optional: true

  validates :business_date, :opened_at, presence: true
  validate :location_must_be_branch

  scope :open_days, -> { where(closed_at: nil) }
  scope :for_location, ->(location) { where(location_id: location.is_a?(Location) ? location.id : location) }

  def open?
    closed_at.nil?
  end

  def self.current_for(location)
    open_days.for_location(location).order(opened_at: :desc).first
  end

  def self.ensure_open!(location, date:, user: nil)
    existing = current_for(location)
    return existing if existing

    create!(
      company: location.company,
      location: location,
      business_date: date,
      opened_at: Time.current,
      opened_by: user
    )
  end

  private

  def location_must_be_branch
    return if location.blank? || location.branch?

    errors.add(:location, :must_be_branch)
  end
end
