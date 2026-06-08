# frozen_string_literal: true

class CashDrawerSessionPolicy < ApplicationPolicy
  def show?
    own_session? || admin?
  end

  def count?
    own_session? && record.status == "open"
  end

  def reconcile?
    count?
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
