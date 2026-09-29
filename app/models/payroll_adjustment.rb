# frozen_string_literal: true

class PayrollAdjustment < ApplicationRecord
  include Tenantable
  include MoneyInputs

  money_input :amount_cents

  KINDS = %w[penalty bonus].freeze
  UNIT_TYPES = %w[full_day half_day quarter_day fixed overtime].freeze
  PENALTY_UNIT_TYPES = %w[full_day half_day quarter_day fixed].freeze
  BONUS_UNIT_TYPES = UNIT_TYPES.freeze
  OVERTIME_RATE = 1.5

  belongs_to :user
  belongs_to :recorded_by, class_name: "User"

  monetize :amount_cents

  validates :kind, presence: true, inclusion: { in: KINDS }
  validates :unit_type, presence: true, inclusion: { in: UNIT_TYPES }
  validates :payroll_month, presence: true
  validates :happened_at, presence: true
  validates :amount_cents, numericality: { greater_than: 0 }, if: -> { unit_type == "fixed" }
  validates :overtime_hours, numericality: { greater_than: 0 }, allow_nil: true, if: -> { unit_type == "overtime" }
  validate :fixed_amount_required
  validate :overtime_hours_required
  validate :overtime_bonus_only
  validate :salary_required_for_computed_amount
  validate :payroll_not_finalized

  before_validation :normalize_payroll_month
  before_validation :set_default_happened_at, on: :create
  before_validation :compute_amount, unless: -> { unit_type == "fixed" }

  scope :for_month, ->(month) { where(happened_at: month.beginning_of_month..month.end_of_month) }
  scope :penalties, -> { where(kind: "penalty") }
  scope :bonuses, -> { where(kind: "bonus") }
  # Attendance-grid late penalties / overtime — identified by the auto note so
  # adjustments created on the staff page never appear on the attendance view.
  scope :attendance_late, -> { penalties.where(notes: attendance_late_notes) }
  scope :attendance_overtime, -> { bonuses.where(unit_type: "overtime", notes: attendance_overtime_notes) }

  def self.attendance_late_note
    I18n.t("accounting.attendance.late_note")
  end

  def self.attendance_overtime_note
    I18n.t("accounting.attendance.overtime_note")
  end

  def self.attendance_late_notes
    translated_notes("accounting.attendance.late_note")
  end

  def self.attendance_overtime_notes
    translated_notes("accounting.attendance.overtime_note")
  end

  def self.translated_notes(key)
    I18n.available_locales.map { |locale| I18n.t(key, locale: locale) }.uniq
  end
  private_class_method :translated_notes

  SORTABLE_COLUMNS = %w[kind happened_at unit_type amount_cents notes recorded_by].freeze
  DEFAULT_SORT = "happened_at"
  DEFAULT_SORT_DIRECTION = "desc"

  def penalty?
    kind == "penalty"
  end

  def bonus?
    kind == "bonus"
  end

  def overtime?
    unit_type == "overtime"
  end

  def day_units
    case unit_type
    when "full_day" then 1.to_d
    when "half_day" then 0.5.to_d
    when "quarter_day" then 0.25.to_d
    else 0.to_d
    end
  end

  def signed_amount_cents
    penalty? ? -amount_cents : amount_cents
  end

  def unit_label
    return I18n.t("staff.payroll.overtime_label", hours: overtime_hours.to_f) if overtime?

    I18n.t("staff.payroll.unit_types.#{unit_type}")
  end

  def self.unit_types_for(kind)
    kind.to_s == "bonus" ? BONUS_UNIT_TYPES : PENALTY_UNIT_TYPES
  end

  private

  def normalize_payroll_month
    return if payroll_month.blank?

    self.payroll_month = payroll_month.to_date.beginning_of_month
  end

  def set_default_happened_at
    self.happened_at ||= Date.current
  end

  def compute_amount
    return unless user

    self.amount_cents = case unit_type
                        when "overtime"
                          (overtime_hours.to_f * user.hourly_rate_cents * OVERTIME_RATE).round
                        when "full_day", "half_day", "quarter_day"
                          compute_day_based_amount
                        else
                          amount_cents
                        end
  end

  def compute_day_based_amount
    daily_rate = user.daily_rate_cents
    case unit_type
    when "full_day" then daily_rate
    when "half_day" then (daily_rate / 2.0).round
    when "quarter_day" then (daily_rate / 4.0).round
    end
  end

  def fixed_amount_required
    return unless unit_type == "fixed"
    return if amount_cents.to_i.positive?

    errors.add(:amount_cents, :blank)
  end

  def overtime_hours_required
    return unless unit_type == "overtime"
    return if overtime_hours.to_f.positive?

    errors.add(:overtime_hours, :blank)
  end

  def overtime_bonus_only
    return unless unit_type == "overtime"
    return if bonus?

    errors.add(:unit_type, :invalid)
  end

  def salary_required_for_computed_amount
    return if unit_type == "fixed"
    return if user&.monthly_salary_cents.to_i.positive?

    errors.add(:base, :salary_required)
  end

  # The month's salary is already paid once a PayrollSnapshot exists for it —
  # adding a bonus or penalty after that would change pay nobody is going to
  # recalculate or repay.
  def payroll_not_finalized
    return if user.blank? || payroll_month.blank?
    return unless PayrollSnapshot.exists?(user: user, payroll_month: payroll_month)

    errors.add(:base, :payroll_finalized)
  end
end
