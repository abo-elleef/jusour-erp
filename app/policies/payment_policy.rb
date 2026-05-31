# frozen_string_literal: true

class PaymentPolicy < ApplicationPolicy
  def index?
    user&.can_access_admin?
  end

  def show?
    user&.can_access_admin?
  end

  def create?
    user&.can_access_pos?
  end

  def refund?
    user&.owner? || user&.manager?
  end

  def destroy?
    false
  end
end
