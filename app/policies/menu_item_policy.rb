# frozen_string_literal: true

class MenuItemPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    true
  end

  def new?
    create?
  end

  def create?
    user.can_access_admin?
  end

  def edit?
    update?
  end

  def update?
    user.can_access_admin?
  end

  def destroy?
    user.owner?
  end

  class Scope < Scope
    def resolve
      scope.all
    end
  end
end
