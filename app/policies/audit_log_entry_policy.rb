# frozen_string_literal: true

class AuditLogEntryPolicy < ApplicationPolicy
  def index?
    owner?
  end

  def show?
    owner?
  end

  def create?
    false
  end

  def update?
    false
  end

  def destroy?
    false
  end
end
