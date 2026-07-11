# frozen_string_literal: true

module Accounting
  # Records a payment against a supplier's AP balance without requiring a linked
  # vendor invoice. Used for pre-migration standing balances.
  class RecordDirectApPaymentService
    class Error < StandardError; end

    def initialize(supplier:, user:, treasury:, amount_cents:, description:, payment_date: Date.current)
      @supplier     = supplier
      @user         = user
      @treasury     = treasury
      @amount_cents = amount_cents.to_i
      @description  = description.presence || default_description
      @payment_date = payment_date
    end

    def call
      raise Error, I18n.t("inventory.suppliers.show.direct_ap_payment.errors.no_ap_balance") unless ap_treasury
      raise Error, I18n.t("inventory.suppliers.show.direct_ap_payment.errors.amount_zero")   if @amount_cents <= 0
      raise Error, I18n.t("inventory.suppliers.show.direct_ap_payment.errors.exceeds_balance") if @amount_cents > ap_treasury.balance_cents

      category = ExpenseCategory.find_by!(name: "Vendor purchases", company: @supplier.company)

      ActiveRecord::Base.transaction do
        Expense.create!(
          expense_category: category,
          user:             @user,
          treasury:         @treasury,
          description:      @description,
          amount_cents:     @amount_cents,
          expense_date:     @payment_date,
          recurrence:       "one_time",
          is_auto_generated: true
        )

        ap_treasury.with_lock do
          ap_treasury.apply_balance_delta!(-@amount_cents)
          TreasuryTransaction.create!(
            treasury:          ap_treasury,
            user:              @user,
            amount_cents:      -@amount_cents,
            kind:              "ap_payment",
            description:       @description,
            occurred_on:       @payment_date,
            balance_after_cents: ap_treasury.balance_cents
          )
        end
      end
    end

    private

    def ap_treasury
      @ap_treasury ||= @supplier.ap_treasury
    end

    def default_description
      I18n.t("inventory.suppliers.show.direct_ap_payment.default_description", supplier: @supplier.name)
    end
  end
end
