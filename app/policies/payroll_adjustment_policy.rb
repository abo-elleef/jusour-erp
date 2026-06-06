# frozen_string_literal: true

class PayrollAdjustmentPolicy < ApplicationPolicy
  def create?
    admin?
  end

  def destroy?
    admin?
  end

  class Scope < Scope
    def resolve
      user&.admin_access? ? scope.all : scope.none
    end
  end
end
