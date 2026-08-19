# frozen_string_literal: true

class SupplierIngredient < ApplicationRecord
  belongs_to :supplier
  belongs_to :ingredient

  monetize :price_cents

  validates :ingredient_id, uniqueness: { scope: :supplier_id }

  before_save :clear_other_preferred_links, if: :preferred?
  after_create  :audit_supplier_linked
  after_destroy :audit_supplier_unlinked

  private

  def clear_other_preferred_links
    ingredient.supplier_ingredients.where.not(id: id).update_all(preferred: false)
  end

  def audit_supplier_linked
    write_supplier_audit("supplier_linked")
  end

  def audit_supplier_unlinked
    write_supplier_audit("supplier_unlinked")
  end

  def write_supplier_audit(action)
    next_version = (ingredient.audits.maximum(:version) || 0) + 1

    Audited::Audit.create!(
      auditable:      ingredient,
      associated:     ingredient.company,
      user:           Audited.store[:current_user],
      action:         action,
      audited_changes: { "supplier" => supplier.name },
      version:        next_version
    )
  end
end
