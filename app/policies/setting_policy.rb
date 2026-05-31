# frozen_string_literal: true

class SettingPolicy < ApplicationPolicy
  def index?
    owner?
  end

  def show?
    owner?
  end

  def update?
    owner?
  end

  def create?
    false
  end

  def destroy?
    false
  end
end
