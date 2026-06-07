# frozen_string_literal: true

class TaxRatePolicy < ApplicationPolicy
  def index?
    owner?
  end

  def show?
    owner?
  end

  def create?
    owner?
  end

  def update?
    owner?
  end

  def destroy?
    owner?
  end
end
