# frozen_string_literal: true

class StockTake < ApplicationRecord
  include Tenantable

  STATUSES = %w[in_progress completed cancelled].freeze

  belongs_to :user
  # A count is scoped to one location. Required for new takes; older takes may
  # predate this (kept optional at the association level so they still save).
  belongs_to :location, optional: true
  has_many :stock_take_items, dependent: :destroy

  accepts_nested_attributes_for :stock_take_items

  validates :status, inclusion: { in: STATUSES }
  validates :location, presence: true, on: :create

  scope :recent, -> { order(created_at: :desc) }
end
