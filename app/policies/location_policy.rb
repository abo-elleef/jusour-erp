# frozen_string_literal: true

class LocationPolicy < ApplicationPolicy
  def index?
    admin?
  end

  def show?
    admin?
  end

  def create?
    owner?
  end

  def update?
    owner? || manager?
  end

  def destroy?
    owner?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.where(company: user.company)
    end
  end
end
