# frozen_string_literal: true

class RolePolicy < ApplicationPolicy
  def index?
    owner?
  end

  def show?
    owner?
  end

  def new?
    create?
  end

  def create?
    owner?
  end

  def edit?
    update?
  end

  def update?
    owner?
  end

  def destroy?
    owner? && !record.built_in?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.all
    end
  end
end
