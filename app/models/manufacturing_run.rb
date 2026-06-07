# frozen_string_literal: true

class ManufacturingRun < ApplicationRecord
  belongs_to :manufacturing_template
  belongs_to :user

  validates :runs_count, numericality: { greater_than: 0 }
  validates :occurred_on, presence: true

  scope :recent, -> { order(occurred_on: :desc, created_at: :desc) }
end
