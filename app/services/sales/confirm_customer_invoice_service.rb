# frozen_string_literal: true

module Sales
  # Confirms a draft customer invoice and deducts the sold stock FIFO from the
  # selling location.
  #
  # How the money is recognised depends on how the sale was settled:
  #
  #   on account  — runs the two-limit credit check and raises Accounts Receivable
  #   paid now    — banks the money straight into a treasury, no receivable at all
  #
  # The second path exists because the whole distribution vertical sells this way:
  # a doctor at the counter pays cash or by wallet and walks out. Routing that
  # through AR would raise a debt and clear it in the same breath, and their
  # statements would read as though they were forever in and out of arrears.
  #
  # Cost/COGS is deliberately NOT posted to the ledger here (step-2 decision) —
  # only the physical stock leaves; margin is finalized later via landed cost.
  class ConfirmCustomerInvoiceService
    class Error < StandardError; end
    class CreditBlocked < Error; end

    Result = Struct.new(:invoice, :credit_warning, keyword_init: true)

    def initialize(invoice, user)
      @invoice = invoice
      @user = user
    end

    def call
      validate!
      return settle_now! if @invoice.paid_on_issue?

      customer = @invoice.customer

      # Two-limit credit control against the balance this invoice would create.
      prospective = customer.ar_balance_cents + @invoice.total_cents
      status = customer.credit_status_for(prospective)
      if status == :blocked
        raise CreditBlocked, I18n.t("sales.customer_invoices.errors.credit_blocked",
                                    default: "This sale exceeds the customer's credit limit.")
      end

      ActiveRecord::Base.transaction do
        deduct_stock!
        Accounting::CustomerArLedgerService.new(customer).charge!(
          amount_cents: @invoice.total_cents,
          user: @user,
          occurred_on: @invoice.invoice_date,
          source: @invoice
        )
        @invoice.update!(status: "confirmed", payment_status: "unpaid", confirmed_at: Time.current)
      end

      Result.new(invoice: @invoice, credit_warning: status == :warning)
    end

    private

    # Money in hand: it goes into the treasury for the method used, revenue is
    # recognised against it, and the invoice is settled on the spot. No credit
    # check — nothing is being extended.
    def settle_now!
      treasury = @invoice.treasury ||
                 SettlementTreasury.for(method: @invoice.payment_method, user: @user)
      if treasury.blank?
        raise Error, I18n.t("sales.customer_invoices.errors.no_settlement_treasury",
                            default: "No treasury is set up to receive this payment method.")
      end

      amount_cents = @invoice.total_cents

      ActiveRecord::Base.transaction do
        deduct_stock!
        treasury.with_lock do
          treasury.apply_balance_delta!(amount_cents)
          TreasuryTransaction.create!(
            treasury: treasury, user: @user, amount_cents: amount_cents, kind: "cash_sale",
            description: I18n.t("sales.customer_invoices.treasury_description",
                                number: @invoice.invoice_number,
                                default: "Sale #{@invoice.invoice_number}"),
            occurred_on: @invoice.invoice_date, source_record: @invoice,
            balance_after_cents: treasury.balance_cents
          )
        end
        Accounting::JournalEntryService.record_customer_cash_sale!(
          source: @invoice, treasury: treasury, date: @invoice.invoice_date,
          user: @user, amount_cents: amount_cents
        )
        @invoice.update!(status: "confirmed", payment_status: "paid",
                         amount_paid_cents: amount_cents, treasury: treasury,
                         confirmed_at: Time.current)
      end

      Result.new(invoice: @invoice, credit_warning: false)
    end

    def validate!
      # Only a draft can be confirmed — a historical invoice is already a completed
      # sale from the previous system, and confirming it would post AR and deduct
      # stock for goods that left years ago.
      raise Error, I18n.t("sales.customer_invoices.errors.not_draft", default: "Only a draft invoice can be confirmed.") unless @invoice.draft?
      raise Error, I18n.t("sales.customer_invoices.errors.no_lines", default: "Add at least one line before confirming.") if @invoice.customer_invoice_lines.empty?
      raise Error, I18n.t("sales.customer_invoices.errors.no_location", default: "A selling location is required.") if @invoice.location.blank?
    end

    def deduct_stock!
      @invoice.customer_invoice_lines.includes(:ingredient).each do |line|
        quantity = line.base_quantity
        next if quantity <= 0

        deduct_fifo(line.ingredient, quantity)
      end
    end

    # Consume the sold quantity from the selling location's FIFO batches and record
    # a location-scoped adjustment so on-hand drops. (On-hand may go negative — the
    # app permits that; a low-stock alert fires if warranted.)
    def deduct_fifo(ingredient, quantity)
      remaining = quantity
      ingredient.stock_batches.where(location: @invoice.location).fifo_order.with_stock.each do |batch|
        break if remaining <= 0

        deductable = [batch.quantity_remaining.to_d, remaining].min
        batch.update!(quantity_remaining: batch.quantity_remaining.to_d - deductable)
        remaining -= deductable
      end

      StockAdjustment.create!(
        ingredient: ingredient,
        user: @user,
        location: @invoice.location,
        quantity_delta: -quantity,
        adjustment_type: "customer_sale",
        reason_notes: "Sold via invoice #{@invoice.invoice_number}"
      )

      Inventory::CheckLowStockJob.perform_later(ingredient.id) if ingredient.reload.low_stock?
    end
  end
end
