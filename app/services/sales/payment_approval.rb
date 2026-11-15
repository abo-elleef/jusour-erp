# frozen_string_literal: true

module Sales
  # The one rule for who approves an online payment on a customer invoice, used
  # by the approve/reject actions, the invoice page buttons and the
  # notification.
  #
  #   The method has active approvers → exactly those people (plus the owner,
  #     who can always step in). Holding sales:confirm_payments isn't enough:
  #     the point is that the Vodafone Cash Saif payment goes to Saif's holder.
  #   No approvers (or none still active) → today's rule: anyone whose role
  #     holds sales:confirm_payments, so a method is never left unapprovable.
  module PaymentApproval
    module_function

    PERMISSION = "sales:confirm_payments"

    # Users to notify / allowed to approve this invoice's payment.
    def approvers_for(invoice)
      assigned = assigned_approvers(invoice.sales_payment_method)
      assigned.exists? ? assigned : NotifyService.recipients_for(PERMISSION)
    end

    def can_approve?(user, invoice)
      return false if user.blank?
      return true if user.owner?

      assigned = assigned_approvers(invoice.sales_payment_method)
      return assigned.exists?(id: user.id) if assigned.exists?

      user.can?(PERMISSION)
    end

    # Can this user approve anything at all? Drives the "Payment approvals" link.
    def approver_anywhere?(user)
      return false if user.blank?

      user.owner? || user.can?(PERMISSION) ||
        PaymentMethodApprover.joins(:sales_payment_method)
                             .where(user_id: user.id, sales_payment_methods: { active: true }).exists?
    end

    def assigned_approvers(payment_method)
      return User.none if payment_method.blank?

      payment_method.approvers.where(active: true)
    end
  end
end
