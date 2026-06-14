# frozen_string_literal: true

class PrintLog < ApplicationRecord
  PRINT_TYPES = %w[receipt kitchen bar expo pick_station station].freeze
  STATUSES = %w[pending sent failed skipped].freeze

  belongs_to :order
  belongs_to :printer, optional: true

  validates :print_type, inclusion: { in: PRINT_TYPES }
  validates :status, inclusion: { in: STATUSES }
end
