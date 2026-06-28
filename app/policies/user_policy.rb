# frozen_string_literal: true

class UserPolicy < ApplicationPolicy
  def index?
    user.owner? || user.accountant?
  end

  def show?
    user.owner? || user.accountant? || record == user
  end

  def new?
    create?
  end

  def create?
    user.owner?
  end

  def edit?
    update?
  end

  def update?
    return true if record == user
    return true if user.accountant?
    return false unless user.owner?

    true
  end

  def destroy?
    return false unless user.owner?
    return false if record == user
    return false if record.owner? && User.active.where(role: "owner").where.not(id: record.id).none?

    true
  end

  def activate?
    user.owner? && !record.active?
  end

  def can_edit_role_and_salary?
    user.owner?
  end

  def permitted_roles
    return User::ROLES if user.owner?

    %w[cashier kitchen]
  end

  class Scope < Scope
    def resolve
      (user.owner? || user.accountant?) ? scope.all : scope.where(id: user.id)
    end
  end
end
