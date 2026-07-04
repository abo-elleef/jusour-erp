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
    owner? || accountant?
  end

  def export?
    admin?
  end

  def clock_in?
    user&.can_access_pos?
  end

  def clock_out?
    clock_in?
  end

  class Scope < Scope
    def resolve
      if user&.admin_access?
        scope.where(company_id: user.company_id)
      elsif user&.cashier?
        scope.where(user_id: user.id, company_id: user.company_id)
      else
        scope.none
      end
    end
  end
end
