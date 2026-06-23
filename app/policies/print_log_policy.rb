# frozen_string_literal: true

class PrintLogPolicy < ApplicationPolicy
  def pending?
    user.can_access_pos?
  end

  def payload?
    pos_access_same_company?
  end

  def confirm?
    pos_access_same_company?
  end

  class Scope < Scope
    def resolve
      scope.joins(:order).where(orders: { company_id: user.company_id })
    end
  end

  private

  def pos_access_same_company?
    user.can_access_pos? && record.order.company_id == user.company_id
  end
end
