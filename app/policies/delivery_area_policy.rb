# frozen_string_literal: true

# A branch's delivery areas are part of its setup, so they follow the same
# permission as editing the branch itself.
class DeliveryAreaPolicy < ApplicationPolicy
  def index?
    manage?
  end

  def create?
    manage?
  end

  def update?
    manage?
  end

  def destroy?
    manage?
  end

  private

  def manage?
    user.can?("locations:manage")
  end
end
