# frozen_string_literal: true

class ManufacturingRun < ApplicationRecord
  belongs_to :manufacturing_template
  belongs_to :user
  belongs_to :location, optional: true

  validates :runs_count, numericality: { greater_than: 0 }
  validates :occurred_on, presence: true
  validates :shelf_life_days, numericality: { only_integer: true, greater_than: 0 }

  scope :recent, -> { order(occurred_on: :desc, created_at: :desc) }

  def output_expires_on
    occurred_on + shelf_life_days.days
  end
end
