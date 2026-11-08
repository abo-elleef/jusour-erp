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

  # Table-service branches hand a table over between cashiers (shift change, someone
  # covering the floor), so any POS cashier may pick up a table's open draft there.
  def resume_table?
    record.draft? && record.table? && record.location&.table_service? && user.can_access_pos?
  end

  def submit?
    update?
  end

  # Deliberately not conditional on payment: an order handed over now and settled
  # later is exactly what this is for. It stays on Collect Payment either way.
  def complete?
    return false if record.cancelled? || record.completed?
    return false if record.draft? && record.order_items.empty?

    user.can_access_pos?
  end

  def complete_all?
    user.can_access_pos?
  end

  # Money in one press, so it is not for anyone who can merely ring a sale.
  def collect_all_cash?
    user.owner? || user.manager?
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

  # A cashier may throw away their own cart, and only while it is still a cart.
  # Anything paid against, or anything that has left `draft`, is a record of
  # something that happened — that gets voided by a manager, not deleted.
  def destroy?
    return false unless record.draft?
    return false if record.payments.any?

    user.can_access_pos? && record.user_id == user.id
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
