# frozen_string_literal: true

class UserPolicy < ApplicationPolicy
  def index?
    admin?
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
    return false if record == user

    owner? || (manager? && staff_role?(record))
  end

  def destroy?
    return false unless owner?
    return false if record == user
    return false if record.owner? && User.where(role: "owner").count <= 1

    !record.orders.exists?
  end

  private

  def staff_role?(target)
    target.cashier? || target.kitchen?
  end
end
