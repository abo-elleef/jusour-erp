# frozen_string_literal: true

class AccountingPolicy < ApplicationPolicy
  def index?
    admin?
  end

  def show?
    admin?
  end

  def new?
    create?
  end

  def create?
    admin?
  end

  def edit?
    update?
  end

  def update?
    admin?
  end

  def destroy?
    owner?
  end

  def export?
    admin?
  end

  def clock_in?
    owner? || manager? || user&.cashier?
  end

  def clock_out?
    clock_in?
  end

  class Scope < Scope
    def resolve
      if user&.admin_access?
        scope.all
      elsif user&.cashier?
        scope.where(user_id: user.id)
      else
        scope.none
      end
    end
  end
end
