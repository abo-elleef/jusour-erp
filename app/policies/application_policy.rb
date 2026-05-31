# frozen_string_literal: true

class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    raise Pundit::NotAuthorizedError, "must be logged in" unless user

    @user = user
    @record = record
  end

  def index?
    false
  end

  def show?
    false
  end

  def create?
    false
  end

  def update?
    false
  end

  def destroy?
    false
  end

  def new?
    create?
  end

  def edit?
    update?
  end

  def owner?
    user.owner?
  end

  def manager?
    user.manager?
  end

  def admin?
    user.can_access_admin?
  end

  class Scope
    def initialize(user, scope)
      raise Pundit::NotAuthorizedError, "must be logged in" unless user

      @user = user
      @scope = scope
    end

    attr_reader :user, :scope

    def resolve
      scope.all
    end
  end
end
