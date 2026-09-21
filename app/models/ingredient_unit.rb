# frozen_string_literal: true

# An alternate unit an ingredient can be measured in (e.g. a gallon for an
# ingredient stocked in ml). `base_units_per_unit` is how many of the
# ingredient's base unit one of this unit equals — "1 <unit> = N <base unit>".
class IngredientUnit < ApplicationRecord
  include Tenantable
  include UnitReferenced

  belongs_to :ingredient
  references_unit :unit, column: :unit_id, required: true

  validates :unit_id, uniqueness: { scope: :ingredient_id }
  validates :base_units_per_unit, numericality: { greater_than: 0 }
  validate :unit_differs_from_base
  validate :unit_belongs_to_company

  before_save  :clear_other_purchase_units, if: :purchase_unit?
  after_create  :audit_unit_added
  after_update  :audit_unit_changed, if: :saved_change_to_purchase_unit?
  after_update  :audit_rate_changed, if: :saved_change_to_base_units_per_unit?
  after_destroy :audit_unit_removed

  private

  def audit_unit_added
    write_unit_audit("unit_added", "unit" => unit_ref&.name)
  end

  def audit_unit_changed
    _was, now = saved_change_to_purchase_unit
    action = now ? "unit_marked_purchase" : "unit_unmarked_purchase"
    write_unit_audit(action, "unit" => unit_ref&.name)
  end

  # The rate reinterprets every quantity ever entered in this unit, so a change
  # to it belongs in the ingredient's history alongside the unit being added or
  # dropped — particularly now that it can be corrected in bulk from the
  # conversion review rather than one ingredient form at a time.
  def audit_rate_changed
    write_unit_audit("unit_rate_changed",
      "unit" => unit_ref&.name,
      "base_units_per_unit" => saved_change_to_base_units_per_unit)
  end

  def audit_unit_removed
    write_unit_audit("unit_removed", "unit" => unit_ref&.name)
  end

  def write_unit_audit(action, changes = {})
    next_version = (ingredient.audits.maximum(:version) || 0) + 1
    Audited::Audit.create!(
      auditable:       ingredient,
      associated:      ingredient.company,
      user:            Audited.store[:current_user],
      action:          action,
      audited_changes: changes,
      version:         next_version
    )
  end

  def clear_other_purchase_units
    ingredient.ingredient_units.where.not(id: id).update_all(purchase_unit: false)
  end

  def unit_differs_from_base
    return if ingredient.blank? || unit_id.blank?
    return unless unit_id == ingredient.unit_id

    errors.add(:unit, :cannot_equal_base_unit)
  end

  def unit_belongs_to_company
    return if unit_ref.blank? || company.blank?
    return if unit_ref.company_id == company_id

    errors.add(:unit, :not_available)
  end
end
