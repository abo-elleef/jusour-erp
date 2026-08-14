# frozen_string_literal: true

class ManufacturingRun < ApplicationRecord
  include Tenantable
  include UnitReferenced

  belongs_to :manufacturing_template
  belongs_to :user
  belongs_to :location, optional: true
  belongs_to :reversed_by, class_name: "User", optional: true
  references_unit :main_input_unit, column: :main_input_unit_id

  before_validation :assign_run_number, on: :create

  validates :runs_count, numericality: { greater_than: 0 }
  validates :occurred_on, presence: true
  validates :shelf_life_days, numericality: { only_integer: true, greater_than: 0 }
  validates :run_number, presence: true, uniqueness: { scope: :company_id, case_sensitive: false }

  scope :recent, -> { order(occurred_on: :desc, created_at: :desc) }

  # "MFG-<year>-<sequence>", per company, resetting each year — same method as
  # vendor invoices and journal entries.
  def self.next_run_number(company: Current.company, year: Date.current.year)
    prefix = "MFG-#{year}-"
    return "#{prefix}00001" if company.blank?

    max_seq = unscoped_by_company
      .where(company_id: company.id)
      .where("run_number ~ ?", "^MFG-#{year}-[0-9]+$")
      .maximum(Arel.sql("CAST(SUBSTRING(run_number FROM #{prefix.length + 1}) AS INTEGER)"))

    format("%s%05d", prefix, (max_seq || 0) + 1)
  end

  def output_expires_on
    occurred_on + shelf_life_days.days
  end

  # True when this run was sized from a main-ingredient amount rather than an
  # explicit run count.
  def main_ingredient_driven?
    main_input_quantity.present?
  end

  def reversed?
    reversed_at.present?
  end

  def output_batch
    return if location_id.blank? || run_number.blank?

    manufacturing_template.output_ingredient.stock_batches
      .where(location_id: location_id, batch_reference: run_number)
      .order(:created_at)
      .last
  end

  # Undo is allowed only while the produced batch is still fully unused.
  def reversible?
    return false if reversed?
    return false if location_id.blank?

    batch = output_batch
    batch.present? && batch.quantity_remaining.to_d >= batch.quantity_received.to_d
  end

  private

  # A run belongs to the same company as its template.
  def assign_company
    self.company ||= manufacturing_template&.company || Current.company
  end

  def assign_run_number
    return if run_number.present?

    self.run_number = self.class.next_run_number(
      company: company || Current.company,
      year: (occurred_on || Date.current).year
    )
  end
end
