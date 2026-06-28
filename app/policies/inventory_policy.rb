# frozen_string_literal: true

class InventoryPolicy < ApplicationPolicy
  def index?
    manager_access?
  end

  def show?
    manager_access?
  end

  def create?
    manager_access?
  end

  def update?
    manager_access?
  end

  def destroy?
    owner? || accountant?
  end

  def adjust?
    manager_access?
  end

  def complete?
    manager_access?
  end

  def record_vendor_invoice_payment?
    manager_access?
  end

  private

  def manager_access?
    user&.can_access_admin?
  end
end
