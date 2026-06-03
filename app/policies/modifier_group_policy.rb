# frozen_string_literal: true

class ModifierGroupPolicy < ApplicationPolicy
  def index?
    user.can_access_admin?
  end

  def show?
    user.can_access_admin?
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
