# frozen_string_literal: true

class Company < ApplicationRecord
  has_many :users, dependent: :destroy
  has_many :locations, dependent: :destroy
  has_many :orders, dependent: :destroy
  has_many :units, dependent: :destroy
  has_many :attendance_statuses, dependent: :destroy
  has_many :staff_attendances, dependent: :destroy
  has_many :cash_drawer_sessions, dependent: :destroy
  has_many :customers, dependent: :destroy
  has_associated_audits

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true, format: { with: /\A[a-z0-9\-]+\z/ }
  validates :timezone, :currency, :locale, presence: true

  after_create :seed_default_units
  after_create :seed_default_attendance_statuses
  after_create :seed_default_roles

  # Names of units this company can use (built-in + custom, active only).
  def unit_names
    units.active.pluck(:name)
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[name slug active created_at]
  end

  private

  def seed_default_units
    Unit.seed_defaults!(self)
  end

  def seed_default_attendance_statuses
    AttendanceStatus.seed_defaults!(self)
  end

  def seed_default_roles
    Roles::Seeder.call(self)
  end
end
