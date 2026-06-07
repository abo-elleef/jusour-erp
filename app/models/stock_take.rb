# frozen_string_literal: true

class StockTake < ApplicationRecord
  include Tenantable

  STATUSES = %w[in_progress completed cancelled].freeze

  belongs_to :user
  has_many :stock_take_items, dependent: :destroy

  accepts_nested_attributes_for :stock_take_items

  validates :status, inclusion: { in: STATUSES }

  scope :recent, -> { order(created_at: :desc) }
end
