# frozen_string_literal: true

class ProductionPolicy < ApplicationPolicy
  def index?
    user&.can_access_production?
  end

  def create?
    user&.can_access_production?
  end
end
