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

  # Owner-only, and deliberately not a permission key. Marking an invoice
  # historical asserts that money already left for it — it settles a balance
  # without any cash movement to audit against, so it stays with the account
  # owner rather than being delegable through the role editor. Same reasoning as
  # `duplicate?` above.
  def mark_invoice_historical?
    user&.owner?
  end

  def record_vendor_invoice_payment?
    user&.can?("inventory:finance")
  end

  def reverse_vendor_invoice_payment?
    user&.can?("inventory:finance")
  end
end
