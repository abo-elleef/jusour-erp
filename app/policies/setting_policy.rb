# frozen_string_literal: true

class SettingPolicy < ApplicationPolicy
  def index?
    owner? || accountant?
  end

  def show?
    owner? || accountant?
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
