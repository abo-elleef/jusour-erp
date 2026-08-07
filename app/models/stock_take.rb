# frozen_string_literal: true

class StockTake < ApplicationRecord
  include Tenantable

  STATUSES = %w[in_progress completing completed cancelled failed].freeze
  # Location cannot start another take while a count is open or being applied.
  ACTIVE_STATUSES = %w[in_progress completing].freeze

  belongs_to :user
  # A count is scoped to one location. Required for new takes; older takes may
  # predate this (kept optional at the association level so they still save).
  belongs_to :location, optional: true
  has_many :stock_take_items, dependent: :destroy

  accepts_nested_attributes_for :stock_take_items

  validates :status, inclusion: { in: STATUSES }
  validates :location, presence: true, on: :create

  scope :recent, -> { order(created_at: :desc) }
  scope :active, -> { where(status: ACTIVE_STATUSES) }

  def active?
    ACTIVE_STATUSES.include?(status)
  end

  def completable?
    status.in?(%w[in_progress failed])
  end
end
