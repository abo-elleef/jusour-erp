# frozen_string_literal: true

class PayrollSnapshotPolicy < ApplicationPolicy
  def create?
    user&.admin_access?
  end

  class Scope < Scope
    def resolve
      user&.admin_access? ? scope.all : scope.none
    end
  end
end
