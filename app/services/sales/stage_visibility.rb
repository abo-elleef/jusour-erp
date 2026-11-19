# frozen_string_literal: true

module Sales
  # Applies the owner's role × invoice-stage grid (Sales::StageAccess).
  #
  # Seeing:
  #   - The owner sees everything.
  #   - A role with no grid rows sees every stage (today's behaviour, so nothing
  #     changes until the owner configures it).
  #   - Otherwise only the stages ticked "can see".
  #   - Always, whatever the grid says: invoices you recorded or are the
  #     salesperson on, and invoices awaiting a payment you can approve — so
  #     nobody loses their own work or an approval they're responsible for.
  #
  # Notifying: when an invoice enters a stage, active members of every role that
  # ticked "notify" for it — except whoever made the change, and except the
  # payment approvers already told by Sales::NotifyService for that stage.
  module StageVisibility
    module_function

    def configured?(role)
      role.present? && StageAccess.where(role_id: role.id).exists?
    end

    def visible_stages(user)
      return CustomerInvoice::STAGES if user.owner?

      role = user.effective_role
      return CustomerInvoice::STAGES unless configured?(role)

      stages = StageAccess.where(role_id: role.id, can_see: true).pluck(:stage)
      stages |= ["pending_payment_confirmation"] if PaymentApproval.approver_anywhere?(user)
      stages
    end

    def all_stages?(user)
      (CustomerInvoice::STAGES - visible_stages(user)).empty?
    end

    # Narrows an invoice relation to what this user may see.
    def scope_for(user, relation = CustomerInvoice.all)
      return relation if all_stages?(user)

      visible = CustomerInvoice.in_stages(visible_stages(user))
        .or(CustomerInvoice.where(user_id: user.id))
        .or(CustomerInvoice.where(salesperson_id: user.id))
      relation.where(id: visible.select(:id))
    end

    def can_see?(user, invoice)
      return true if all_stages?(user)
      return true if invoice.user_id == user.id || invoice.salesperson_id == user.id
      return true if invoice.pending_payment_confirmation? && PaymentApproval.can_approve?(user, invoice)

      visible_stages(user).include?(invoice.stage)
    end

    # Active users whose role asked to be told when an invoice enters `stage`.
    def notify_recipients(stage)
      role_ids = StageAccess.where(stage: stage, notify: true, can_see: true).select(:role_id)
      roles = Role.where(id: role_ids)
      User.where(role_id: roles.select(:id))
          .or(User.where(role_id: nil, role: roles.where.not(key: nil).select(:key)))
          .where(active: true)
    end

    def notify_stage_entered(invoice, stage, actor: nil)
      return if stage == "historical" # imported history; nothing happened just now

      recipients = notify_recipients(stage)
      recipients = recipients.where.not(id: actor.id) if actor
      if stage == "pending_payment_confirmation"
        recipients = recipients.where.not(id: PaymentApproval.approvers_for(invoice).select(:id))
      end

      recipients.find_each do |user|
        # A rep limited to their own content isn't told about other reps' invoices.
        next unless OwnershipScope.for(user).owns_invoice?(invoice)

        Notification.create!(
          recipient: user, company: invoice.company, notification_type: "sales",
          params: { message_key: "customer_invoice_stage_entered",
                    message_params: { invoice_number: invoice.invoice_number,
                                      customer_invoice_id: invoice.id, stage: stage }.deep_stringify_keys,
                    customer_invoice_id: invoice.id }
        )
      end
    end
  end
end
