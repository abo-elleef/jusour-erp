# frozen_string_literal: true

module Sales
  # The ONE rule for "a salesperson sees only their own content" (Bazzar
  # slice E). Controllers, pickers, statements and reports all ask this object;
  # none of them repeat the rule.
  #
  #   scope = Sales::OwnershipScope.for(current_user)
  #   scope.leads / scope.customers / scope.invoices / scope.credit_notes
  #   scope.can_see_lead?(lead) / can_see_customer? / can_see_invoice? / ...
  #
  # Who is limited: a user whose company runs the distribution sales area
  # (credit sales or leads) and who is neither the owner nor holds
  # sales:see_all. Everybody else — and every restaurant, whose cashiers create
  # and pick customers at the POS — gets the relations back untouched.
  #
  # What a limited user sees:
  #   Leads       — assigned to them.
  #   Customers   — assigned to them. Unassigned customers are hidden until a
  #                 manager assigns them.
  #   Invoices    — of a customer assigned to them, or recorded (user_id) or
  #                 sold (salesperson_id) by them; AND visible to their role
  #                 under the owner's role × stage grid (Sales::StageVisibility,
  #                 which itself always keeps the ones they recorded or sold).
  #                 Plus, always, invoices waiting on a payment they approve
  #                 (Sales::PaymentApproval).
  #   Credit notes — of a customer assigned to them, or recorded by them.
  #
  # Reports read #report_invoices / #report_credit_notes: the same ownership
  # rule without the stage grid, which governs the workflow pages, not a rep's
  # own sales figures.
  class OwnershipScope
    PERMISSION = "sales:see_all"
    SALES_FEATURES = %i[ar_credit_sales leads].freeze

    def self.for(user)
      new(user)
    end

    # Does this company have the distribution sales area at all? Off for
    # restaurants, so nothing here ever narrows a POS customer list.
    def self.applies_to?(company)
      company.present? && SALES_FEATURES.any? { |feature| company.feature_enabled?(feature) }
    end

    attr_reader :user

    def initialize(user)
      @user = user
    end

    def limited?
      return @limited if defined?(@limited)

      @limited = user.present? && !user.owner? && !user.can?(PERMISSION) && self.class.applies_to?(user.company)
    end

    # Managers (and the owner) set and reassign a customer's salesperson.
    def manages_assignment?
      user.present? && self.class.applies_to?(user.company) && (user.owner? || user.can?(PERMISSION))
    end

    # --- Relations -----------------------------------------------------------

    def leads(relation = Lead.all)
      return relation unless limited?

      relation.where(assigned_user_id: user.id)
    end

    def customers(relation = Customer.all)
      return relation unless limited?

      relation.where(assigned_user_id: user.id)
    end

    def invoices(relation = CustomerInvoice.all)
      return StageVisibility.scope_for(user, relation) unless limited?

      visible = StageVisibility.scope_for(user, owned_invoices).or(approvable_invoices)
      relation.where(id: visible.select(:id))
    end

    def credit_notes(relation = CreditNote.all)
      return relation unless limited?

      relation.where(customer_id: owned_customer_ids).or(relation.where(user_id: user.id))
    end

    def report_invoices(relation)
      return relation unless limited?

      relation.where(id: owned_invoices.select(:id))
    end

    def report_credit_notes(relation)
      credit_notes(relation)
    end

    # --- Single records ------------------------------------------------------

    def can_see_lead?(lead)
      !limited? || lead.assigned_user_id == user.id
    end

    def can_see_customer?(customer)
      !limited? || customer.assigned_user_id == user.id
    end

    # Ownership AND the owner's role × stage grid — what the invoice page shows.
    def can_see_invoice?(invoice)
      StageVisibility.can_see?(user, invoice) && owns_invoice?(invoice)
    end

    # Ownership alone: theirs by customer, recorder or salesperson, or waiting
    # on a payment they approve. Guards every action on someone else's invoice.
    def owns_invoice?(invoice)
      return true unless limited?
      return true if invoice.pending_payment_confirmation? && PaymentApproval.can_approve?(user, invoice)

      owned_invoice?(invoice)
    end

    def can_see_credit_note?(credit_note)
      return true unless limited?

      credit_note.user_id == user.id || credit_note.customer&.assigned_user_id == user.id
    end

    private

    def owned_customer_ids
      Customer.where(assigned_user_id: user.id).select(:id)
    end

    def owned_invoices
      CustomerInvoice.where(customer_id: owned_customer_ids)
        .or(CustomerInvoice.where(user_id: user.id))
        .or(CustomerInvoice.where(salesperson_id: user.id))
    end

    def owned_invoice?(invoice)
      invoice.user_id == user.id || invoice.salesperson_id == user.id ||
        invoice.customer&.assigned_user_id == user.id
    end

    # Invoices waiting on a payment this user approves — the SQL twin of
    # PaymentApproval.can_approve?: the method's own active approvers when it
    # has any, otherwise anyone holding sales:confirm_payments.
    def approvable_invoices
      pending = CustomerInvoice.pending_payment_confirmation
      own_methods = PaymentMethodApprover.joins(:user)
        .where(user_id: user.id, users: { active: true }).select(:sales_payment_method_id)
      approvable = pending.where(sales_payment_method_id: own_methods)
      return approvable unless user.can?(PaymentApproval::PERMISSION)

      staffed_methods = PaymentMethodApprover.joins(:user).where(users: { active: true }).select(:sales_payment_method_id)
      approvable.or(pending.where.not(sales_payment_method_id: staffed_methods))
                .or(pending.where(sales_payment_method_id: nil))
    end
  end
end
