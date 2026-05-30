# frozen_string_literal: true

class MenuItemPolicy < ApplicationPolicy
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
end
