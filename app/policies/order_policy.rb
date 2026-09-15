# frozen_string_literal: true

class OrderPolicy < ApplicationPolicy
  def index?
    user.can_access_pos? || user.can_access_admin?
  end

  def index_for_payment?
    user.can_access_pos?
  end

  def show?
    user.can_access_pos? || user.can_access_admin?
  end

  def checkout?
    record_payment?
  end

  # Drafts are payable too: a part-paid cart and an order rung up to be settled
  # later are both drafts, and Collect Payment exists to close exactly those. An
  # empty cart stays out — there is nothing to collect on it.
  def record_payment?
    return false if record.cancelled?
    return false if record.draft? && record.order_items.empty?

    user.can_access_pos? && record.amount_due_cents.positive?
  end

  def create?
    user.can_access_pos?
  end

  def update?
    return false if record.cancelled?
    return false if record.completed? && record.fully_paid?
    return user.can_access_pos? if !record.draft?

    create? && record.draft?
  end

  def submit?
    update?
  end

  def apply_discount?
    user.can_access_pos?
  end

  def manager_discount?
    user.owner? || user.manager?
  end

  def change_payment_method?
    user.owner? || user.manager?
  end

  def void?
    (user.owner? || user.manager?) && !record.completed?
  end

  def refund?
    (user.owner? || user.manager?) && record.completed?
  end

  def split?
    user.can_access_pos?
  end

  def merge?
    user.owner? || user.manager?
  end

  def destroy?
    false
  end

  class Scope < Scope
    def resolve
      if user.owner? || user.manager? || user.accountant?
        scope.all
      elsif user.cashier?
        scope.where(user: user)
      else
        scope.none
      end
    end
  end
end
