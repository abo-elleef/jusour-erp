# frozen_string_literal: true

class CashDrawerSessionPolicy < ApplicationPolicy
  def show?
    own_session? || admin?
  end

  # The slip is the record of a count, so only a drawer that has been counted has one.
  def print_slip?
    show? && record.counted_cash_cents.present?
  end

  def count?
    own_session? && record.status == "open"
  end

  def reconcile?
    count?
  end

  # Takes a count and its ledger entries back off the books, so it is not for
  # whoever can merely see the drawer.
  def reopen?
    (user.owner? || user.super_manager?) && record.status != "open"
  end

  def open_drawer?
    user.can_access_pos?
  end

  class Scope < Scope
    def resolve
      if user.can_access_admin?
        scope.all
      elsif user.can_access_pos?
        scope.where(user_id: user.id)
      else
        scope.none
      end
    end
  end

  private

  def own_session?
    record.user_id == user.id
  end
end
