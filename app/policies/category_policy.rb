# frozen_string_literal: true

class CategoryPolicy < ApplicationPolicy
  def index?
    admin?
  end

  def create?
    admin?
  end

  def update?
    admin?
  end

  def destroy?
    owner?
  end
end
