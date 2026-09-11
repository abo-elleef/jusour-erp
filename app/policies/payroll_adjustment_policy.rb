# frozen_string_literal: true

class PayrollAdjustmentPolicy < ApplicationPolicy
  def create?
    admin?
  end

  def destroy?
    admin? && user.can?("attendance:waive_penalties")
  end

  class Scope < Scope
    def resolve
      user&.admin_access? ? scope.where(company_id: user.company_id) : scope.none
    end
  end
end
