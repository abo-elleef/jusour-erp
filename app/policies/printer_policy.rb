# frozen_string_literal: true

class PrinterPolicy < ApplicationPolicy
  def index?
    admin?
  end

  def show?
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

  def test_print?
    update?
  end

  class Scope < Scope
    def resolve
      scope.all
    end
  end
end
