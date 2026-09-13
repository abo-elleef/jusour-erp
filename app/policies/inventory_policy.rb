# frozen_string_literal: true

class InventoryPolicy < ApplicationPolicy
  def index?
    user&.can?("inventory:view")
  end

  def show?
    user&.can?("inventory:view")
  end

  def create?
    user&.can?("inventory:manage")
  end

  def update?
    user&.can?("inventory:manage")
  end

  def destroy?
    user&.can?("inventory:manage")
  end

  def adjust?
    user&.can?("inventory:manage")
  end

  # Owner-only, deliberately not a permission key: copying a transfer reproduces
  # someone else's request wholesale, and we want that kept to the account owner
  # rather than delegable through the role editor.
  def duplicate?
    user&.owner?
  end

  def complete?
    user&.can?("inventory:manage")
  end

  def record_vendor_invoice_payment?
    user&.can?("inventory:finance")
  end

  def reverse_vendor_invoice_payment?
    user&.can?("inventory:finance")
  end
end
