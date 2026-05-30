# frozen_string_literal: true

class OrderPolicy < ApplicationPolicy
  def index?
    admin?
  end

  def index_for_payment?
    cashier_access?
  end

  def show?
    admin? || cashier_access? || kitchen_access?
  end

  def checkout?
    record_payment?
  end

  def record_payment?
    return false if record.cancelled? || record.draft?

    cashier_access? && record.amount_due_cents.positive?
  end

  def create?
    user&.cashier? || admin?
  end

  def update?
    return false if record.cancelled?
    return false if record.completed? && record.fully_paid?
    return cashier_access? if !record.draft?

    create? && record.draft?
  end

  def submit?
    update?
  end

  def void?
    admin? && !record.completed?
  end

  def refund?
    admin? && record.completed?
  end

  def split?
    update?
  end

  def merge?
    update?
  end

  private

  def cashier_access?
    user&.cashier? || admin?
  end

  def kitchen_access?
    user&.kitchen? || admin?
  end
end
