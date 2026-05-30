# frozen_string_literal: true

class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    @user = user
    @record = record
  end

  def owner?
    user&.owner?
  end

  def manager?
    user&.manager?
  end

  def admin?
    user&.admin_access?
  end

  class Scope
    def initialize(user, scope)
      @user = user
      @scope = scope
    end

    attr_reader :user, :scope

    def resolve
      scope.all
    end
  end
end
