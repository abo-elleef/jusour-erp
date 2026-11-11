# frozen_string_literal: true

class PrintLogPolicy < ApplicationPolicy
  def pending?
    user.can_access_pos?
  end

  def payload?
    pos_access_same_company?
  end

  def failed?
    user.can_access_pos?
  end

  def retry?
    pos_access_same_company?
  end

  def confirm?
    pos_access_same_company?
  end

  # Marking a failed ticket as dealt with by hand (no reprint).
  def handle?
    pos_access_same_company?
  end

  class Scope < Scope
    def resolve
      scope.left_joins(:order, :cash_drawer_session)
           .where("orders.company_id = :c OR cash_drawer_sessions.company_id = :c", c: user.company_id)
    end
  end

  private

  def pos_access_same_company?
    user.can_access_pos? && record.company_id == user.company_id
  end
end
