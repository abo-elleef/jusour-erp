# frozen_string_literal: true

class ShiftLogPolicy < AccountingPolicy
  def clock_out?
    return false unless clock_in?

    owner? || manager? || record.user_id == user.id
  end

  class Scope < AccountingPolicy::Scope
    def resolve
      if user&.admin_access?
        scope.all
      elsif user&.cashier?
        scope.where(user_id: user.id)
      else
        scope.none
      end
    end
  end
end
