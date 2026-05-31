# frozen_string_literal: true

class ShiftLogPolicy < ApplicationPolicy
  def index?
    user.can_access_admin? || user.cashier?
  end

  def show?
    user.can_access_admin? || record.user_id == user.id
  end

  def clock_in?
    user.can_access_pos?
  end

  def clock_out?
    return false unless clock_in?

    user.can_access_admin? || record.user_id == user.id
  end

  def update?
    user.can_access_admin?
  end

  def create?
    clock_in?
  end

  def destroy?
    false
  end

  class Scope < Scope
    def resolve
      if user.can_access_admin?
        scope.all
      elsif user.cashier?
        scope.where(user_id: user.id)
      else
        scope.none
      end
    end
  end
end
