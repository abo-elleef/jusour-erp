# frozen_string_literal: true

# A symbol a manager can enter in an attendance cell, and what it means for pay.
# The pay meaning lives in data (paid_fraction / penalty_days) so new symbols are
# a row, not a code change.
class AttendanceStatus < ApplicationRecord
  include Tenantable

  has_many :staff_attendances, dependent: :restrict_with_error

  validates :code, presence: true, uniqueness: { scope: :company_id, case_sensitive: false }
  validates :symbol, presence: true, uniqueness: { scope: :company_id, case_sensitive: false }
  validates :label, presence: true
  validates :paid_fraction, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }
  validates :penalty_days, numericality: { greater_than_or_equal_to: 0 }
  validates :bonus_days, numericality: { greater_than_or_equal_to: 0 }

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position, :symbol) }

  #  symbol  meaning              paid    bonus  penalty
  #  P       present              1       0      0
  #  PP      present + bonus      1       1      0   (a paid day AND +1 bonus day)
  #  O       planned off          1       0      0
  #  A       excused absence      0       0      0   (informed → unpaid, no penalty)
  #  X       unexcused absence    0       0      1   (unpaid day + 1 penalty day = -2)
  #  H       half day             0.5     0      0
  DEFAULTS = [
    { code: "present",       symbol: "P",  label: "Present",           paid_fraction: 1,   bonus_days: 0, penalty_days: 0, color: "emerald", position: 1 },
    { code: "present_bonus", symbol: "PP", label: "Present + bonus",   paid_fraction: 1,   bonus_days: 1, penalty_days: 0, color: "teal",    position: 2 },
    { code: "off",           symbol: "O",  label: "Planned off",       paid_fraction: 1,   bonus_days: 0, penalty_days: 0, color: "blue",    position: 3 },
    { code: "half_day",      symbol: "H",  label: "Half day",          paid_fraction: 0.5, bonus_days: 0, penalty_days: 0, color: "indigo",  position: 4 },
    { code: "excused",       symbol: "A",  label: "Excused absence",   paid_fraction: 0,   bonus_days: 0, penalty_days: 0, color: "amber",   position: 5 },
    { code: "unexcused",     symbol: "X",  label: "Unexcused absence", paid_fraction: 0,   bonus_days: 0, penalty_days: 1, color: "red",     position: 6 }
  ].freeze

  # Idempotent — safe to call repeatedly (mirrors Unit.seed_defaults!).
  def self.seed_defaults!(company)
    DEFAULTS.each do |attrs|
      company.attendance_statuses.where(code: attrs[:code]).first ||
        company.attendance_statuses.create!(attrs)
    end
  end

  def paid?
    paid_fraction.to_d.positive?
  end

  # For plain-text contexts (the generic audit-history table) that can't show
  # the grid's colored letter badge — still names the letter code, not just
  # the long label.
  def label_with_symbol
    "#{symbol} · #{label}"
  end
end
