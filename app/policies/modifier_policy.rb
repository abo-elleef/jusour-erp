# frozen_string_literal: true

class ModifierPolicy < ApplicationPolicy
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
end
