# frozen_string_literal: true

class OrderPolicy < ApplicationPolicy
  def index?
    user.can_access_pos? || user.can_access_admin?
  end

  def index_for_payment?
    user.can_access_pos?
  end

  def show?
    user.can_access_pos? || user.can_access_admin?
  end

  def checkout?
    record_payment?
  end

  # Drafts are payable too: a part-paid cart and an order rung up to be settled
  # later are both drafts, and Collect Payment exists to close exactly those. An
  # empty cart stays out — there is nothing to collect on it.
  def record_payment?
    return false if record.cancelled?
    return false if record.draft? && record.order_items.empty?

    user.can_access_pos? && record.amount_due_cents.positive?
  end

  def create?
    user.can_access_pos?
  end

  def update?
    return false if record.cancelled?
    return false if record.completed? && record.fully_paid?
    return user.can_access_pos? if !record.draft?

    create? && record.draft?
  end

  # Table-service branches hand a table over between cashiers (shift change, someone
  # covering the floor), so any POS cashier may pick up a table's open draft there.
  def resume_table?
    record.draft? && record.table? && record.location&.table_service? && user.can_access_pos?
  end

  def submit?
    update?
  end

  # The branch PIN is the real gate (Pos::OrdersController#unlock_edit); this only
  # keeps the button to the people at the register.
  def unlock_edit?
    user.can_access_pos? && (record.editing_placed? || record.unlockable_for_edit?)
  end

  # Completing an order that still owes money (hand it over now, settle later) needs
  # orders:complete_unpaid. A cashier without it completes only fully paid orders,
  # so nothing leaves their shift unpaid by mistake; the rest goes to Collect Payment.
  def complete?
    return false if record.cancelled? || record.completed?
    return false if record.draft? && record.order_items.empty?
    return false unless user.can_access_pos?

    record.fully_paid? || user.can?("orders:complete_unpaid")
  end

  # Why the Complete button is greyed out (nil when it works or isn't relevant).
  # Only "unpaid" is worth explaining; the other refusals just hide the button.
  def complete_blocked_reason
    return if complete?
    return if record.cancelled? || record.completed? || record.draft?
    return unless user.can_access_pos?

    :needs_payment
  end

  def complete_all?
    user.can_access_pos?
  end

  # Any POS user may sweep their own orders from the current shift into their own
  # open drawer. The controller limits it to exactly that set, so this is not a
  # licence to settle anyone else's tickets or an older shift's.
  def collect_all_cash?
    user.can_access_pos?
  end

  def apply_discount?
    user.can_access_pos?
  end

  def manager_discount?
    user.owner? || user.manager?
  end

  # Any cashier: which payments they may move, and until when, is decided per
  # payment by Payments::ChangeMethodService (open drawer, their own drawer).
  def change_payment_method?
    user.can_access_pos? || user.owner? || user.manager?
  end

  # Completed orders too, paid or not: the void refunds what was paid.
  # The admin order page. Anyone who can open it may void; the branch's void-orders
  # PIN is the gate for everyone but owners and managers (void_without_pin?).
  def void?
    return false unless show?
    !record.cancelled?
  end

  # Owners and managers void and reopen orders on the admin page without the
  # branch PIN; everyone else types it.
  def skip_branch_pin?
    user.owner? || user.manager?
  end

  # Voiding from the register. The branch's void-orders PIN is the real gate
  # (Pos::OrdersController#void); this keeps the button to placed orders the admin
  # void would also accept. A draft is discarded instead, not voided.
  def void_with_pin?
    void_at_register_allowed_by_status? && !record.paid_in_closed_drawer?
  end

  # A void the register would take but for money a closed drawer took in: the page
  # says to void it from the admin side instead of offering the PIN.
  def void_needs_admin?
    void_at_register_allowed_by_status? && record.paid_in_closed_drawer?
  end

  # Why the register's Edit items button is greyed out (nil when it works). A key
  # under pos.orders.blocked.edit_items.
  def edit_items_blocked_reason
    return if unlock_edit?
    return :no_access unless user.can_access_pos?
    return :cancelled if record.cancelled?
    return :draft if record.draft?
    return :paid unless record.never_paid?
    return :completed if record.completed?

    :no_access
  end

  # Why the register's Void button is greyed out (nil when it works). A key under
  # pos.orders.blocked.void.
  def void_blocked_reason
    return if void_with_pin?
    return :closed_drawer if void_needs_admin?
    return :no_access unless user.can_access_pos?
    return :cancelled if record.cancelled?
    return :draft if record.draft?

    :no_access
  end

  def refund?
    (user.owner? || user.manager?) && record.completed?
  end

  def split?
    user.can_access_pos?
  end

  def merge?
    user.owner? || user.manager?
  end

  # A cashier may throw away their own cart, and only while it is still a cart.
  # Anything paid against, or anything that has left `draft`, is a record of
  # something that happened — that gets voided by a manager, not deleted.
  def destroy?
    return false unless record.draft?
    return false if record.payments.any?

    user.can_access_pos? && record.user_id == user.id
  end

  private

  def void_at_register_allowed_by_status?
    return false unless user.can_access_pos?
    !(record.draft? || record.cancelled?)
  end

  public

  class Scope < Scope
    def resolve
      if user.owner? || user.manager? || user.accountant?
        scope.all
      elsif user.cashier?
        scope.where(user: user)
      else
        scope.none
      end
    end
  end
end
