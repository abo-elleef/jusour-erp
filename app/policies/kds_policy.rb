# frozen_string_literal: true

class KdsPolicy < ApplicationPolicy
  def view?
    user&.can_access_kds?
  end

  def index?
    view?
  end

  def start?
    view?
  end

  def ready?
    view?
  end
end
