# frozen_string_literal: true

class Location < ApplicationRecord
  include Tenantable

  TYPES = %w[central_kitchen branch].freeze

  belongs_to :company
  has_many :ingredient_locations, dependent: :destroy
  has_many :ingredients, through: :ingredient_locations
  has_many :location_menu_items, dependent: :destroy
  has_many :menu_items, through: :location_menu_items
  has_many :stock_batches, dependent: :nullify
  has_many :stock_adjustments, dependent: :nullify
  has_many :stock_takes, dependent: :nullify
  has_many :manufacturing_runs, dependent: :nullify
  has_many :orders, dependent: :nullify
  has_many :vendor_invoices, dependent: :restrict_with_error
  has_many :printers, dependent: :restrict_with_error
  has_many :outgoing_stock_transfers, class_name: "StockTransfer", foreign_key: :from_location_id, dependent: :restrict_with_error
  has_many :incoming_stock_transfers, class_name: "StockTransfer", foreign_key: :to_location_id, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: { scope: :company_id }
  validates :slug, presence: true, uniqueness: { scope: :company_id },
    format: { with: /\A[a-z0-9\-]+\z/ }
  validates :location_type, presence: true, inclusion: { in: TYPES }

  before_validation :generate_slug, if: -> { slug.blank? && name.present? }

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position, :name) }
  scope :branches, -> { where(location_type: "branch") }
  scope :central_kitchens, -> { where(location_type: "central_kitchen") }
  scope :public_menu_enabled, -> { where(public_menu_enabled: true) }
  scope :publicly_accessible, -> { active.branches.public_menu_enabled }

  before_validation :clear_public_menu_for_non_branches

  def self.ransackable_attributes(_auth_object = nil)
    %w[name location_type active]
  end

  def central_kitchen?
    location_type == "central_kitchen"
  end

  def branch?
    location_type == "branch"
  end

  def ingredient_stock(ingredient)
    ingredient_locations.find_by(ingredient: ingredient)
  end

  private

  def clear_public_menu_for_non_branches
    self.public_menu_enabled = false unless branch?
  end

  def generate_slug
    base = name.to_s.parameterize.presence || "location"
    candidate = base
    counter = 1
    scope = Location.unscoped.where(company_id: company_id).where.not(id: id)
    while scope.exists?(slug: candidate)
      candidate = "#{base}-#{counter}"
      counter += 1
    end
    self.slug = candidate
  end

  def assign_company
    self.company ||= Current.company
  end
end
