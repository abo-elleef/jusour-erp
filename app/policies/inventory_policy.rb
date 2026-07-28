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

  def complete?
    user&.can?("inventory:manage")
  end

  def record_vendor_invoice_payment?
    user&.can?("inventory:manage")
  end
end
