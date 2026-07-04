# frozen_string_literal: true

class TreasuryPolicy < AccountingPolicy
  # Restricted treasuries (e.g. an owner's month-end reserve) are visible and
  # manageable only by owners and managers. Everyone else is treated as if the
  # treasury does not exist.
  def show?
    return owner? || manager? if restricted_record?

    super
  end

  def update?
    return owner? || manager? if restricted_record?

    super
  end

  def destroy?
    return owner? || manager? if restricted_record?

    super
  end

  private

  def restricted_record?
    record.respond_to?(:restricted?) && record.restricted?
  end

  class Scope < Scope
    def resolve
      super.visible_to(user)
    end
  end
end
