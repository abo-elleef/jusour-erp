# frozen_string_literal: true

class OvertimeRule < ApplicationRecord
  validates :name, presence: true
  validates :weekly_threshold_hours, numericality: { greater_than: 0 }, allow_nil: true
  validates :ot_multiplier, numericality: { greater_than: 0 }

  scope :active, -> { where(active: true) }
end
