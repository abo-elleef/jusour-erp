# frozen_string_literal: true

class PayrollAdvancePolicy < ApplicationPolicy
  def create?
    user&.admin_access?
  end

  def destroy?
    return false unless user&.admin_access?
    return false if record.user.payroll_snapshots.exists?(payroll_month: record.payroll_month)

    true
  end

  class Scope < Scope
    def resolve
      user&.admin_access? ? scope.all : scope.none
    end
  end
end
