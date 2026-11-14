# frozen_string_literal: true

# Reviewing self-orders across branches is part of reviewing orders.
class OnlineOrderRequestPolicy < ApplicationPolicy
  def index?
    user.can?("orders:view")
  end
end
