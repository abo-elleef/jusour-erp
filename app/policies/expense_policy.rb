# frozen_string_literal: true

class ExpensePolicy < AccountingPolicy
  def update?
    admin? && !record.is_auto_generated?
  end

  def destroy?
    user.owner? && !record.is_auto_generated?
  end
end
