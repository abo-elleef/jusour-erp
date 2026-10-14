# frozen_string_literal: true

module Sales
  # Confirms a draft customer invoice and deducts the sold stock FIFO from the
  # selling location.
  #
  # How the money is recognised depends on how the sale was settled:
  #
  #   on_account        — runs the two-limit credit check and raises Accounts Receivable
  #   cash               — banks the money straight into a treasury, no receivable at all
  #   online             — same as cash, but only once someone with sales:confirm_payments
  #                        has approved it (see the pending_payment_confirmation gate below)
  #   cash_on_delivery   — confirms (stock leaves) but settles nowhere yet; the shipping
  #                        company isn't charged until Sales::DispatchCustomerInvoiceService
  #                        runs, because nobody is holding our cash until then
  #
  # The paid-now paths exist because the whole distribution vertical sells this way:
  # a doctor at the counter pays cash or by wallet and walks out. Routing that
  # through AR would raise a debt and clear it in the same breath, and their
  # statements would read as though they were forever in and out of arrears.
  #
  # Cost/COGS is deliberately NOT posted to the ledger here (step-2 decision) —
  # only the physical stock leaves; margin is finalized later via landed cost.
  class ConfirmCustomerInvoiceService
    class Error < StandardError; end
    class CreditBlocked < Error; end

    Result = Struct.new(:invoice, :credit_warning, :pending_confirmation, keyword_init: true)

    def initialize(invoice, user)
      @invoice = invoice
      @user = user
    end

    def call
      validate!

      # First time an online-payment draft is confirmed: park it for approval
      # instead of settling anything. Calling this again once it's
      # pending_payment_confirmation (i.e. the approve action) falls through
      # to settle_now! below, same as cash always has.
      if @invoice.draft? && @invoice.online?
        @invoice.update!(status: "pending_payment_confirmation")
        Sales::NotifyService.deliver_payment_pending(@invoice)
        return Result.new(invoice: @invoice, credit_warning: false, pending_confirmation: true)
      end

      return on_account_confirm! if @invoice.on_account?
      return cod_confirm! if @invoice.cash_on_delivery?

      settle_now!
    end

    private

    def on_account_confirm!
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
        customer.increment!(:total_spent_cents, @invoice.total_cents)
      end

      Result.new(invoice: @invoice, credit_warning: status == :warning)
    end

    # Cash-on-delivery: the sale is real and the goods leave now, but nobody is
    # holding our cash yet — the shipping company only becomes accountable for
    # it at dispatch (Sales::DispatchCustomerInvoiceService). No treasury, no
    # revenue posted here; payment_status stays "unpaid" until then.
    def cod_confirm!
      ActiveRecord::Base.transaction do
        deduct_stock!
        @invoice.update!(status: "confirmed", confirmed_at: Time.current)
      end

      Result.new(invoice: @invoice, credit_warning: false)
    end

    # Money in hand: it goes into the treasury for the method used, revenue is
    # recognised against it, and the invoice is settled on the spot. No credit
    # check — nothing is being extended.
    def settle_now!
      treasury = @invoice.treasury || SettlementTreasury.for(invoice: @invoice, user: @user)
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
        @invoice.customer.increment!(:total_spent_cents, amount_cents)
      end

      Result.new(invoice: @invoice, credit_warning: false)
    end

    def validate!
      # A draft starts the flow; pending_payment_confirmation is the same
      # invoice coming back through on approval. Historical/confirmed/void
      # can't be (re-)confirmed.
      unless @invoice.draft? || @invoice.pending_payment_confirmation?
        raise Error, I18n.t("sales.customer_invoices.errors.not_draft", default: "Only a draft invoice can be confirmed.")
      end
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
