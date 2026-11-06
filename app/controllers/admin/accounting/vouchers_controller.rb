# frozen_string_literal: true

require "csv"

module Admin
  module Accounting
    # سند قبض / سند صرف — the document for money crossing a treasury.
    #
    # There is no edit. A voucher records that money moved on a given day; if it
    # is wrong the document is voided, which takes the cash back, and a new one
    # is issued with its own number.
    class VouchersController < BaseController
      # `settles` value for "spread across the party's open invoices".
      OLDEST_FIRST = "oldest_first"

      before_action :set_voucher, only: %i[show destroy]

      def index
        parse_date_range(default_start: Date.current.beginning_of_month)

        @q = Voucher.ransack(params[:q])
        scope = @q.result.includes(:treasury, :user, payment_allocations: :settles)
        scope = scope.on_date_range(@start_date, @end_date)
        scope = scope.where(direction: params[:direction]) if Voucher::DIRECTIONS.include?(params[:direction])
        scope = scope.where(treasury_id: params[:treasury_id]) if params[:treasury_id].present?
        @search = params[:search].to_s.strip
        scope = scope.search_text(@search) if @search.present?

        totals = scope.unscope(:includes).active
        @received_cents = totals.receipts.sum(:amount_cents)
        @paid_cents     = totals.payments.sum(:amount_cents)
        @total_count    = totals.count
        @voided_count   = scope.unscope(:includes).voided.count

        ordered = scope.order(voucher_date: :desc, created_at: :desc)

        if request.format.csv?
          return send_data vouchers_csv(ordered),
                           filename: "vouchers-#{@start_date}-#{@end_date}.csv",
                           type: "text/csv; charset=utf-8"
        end

        @pagy, @vouchers = pagy(:offset, ordered, limit: 50)
        @treasuries = Treasury.active.visible_to(current_user).ordered
      end

      def show
        authorize @voucher
        @journal_entry = JournalEntry.for_source(@voucher).includes(:lines).first
        @allocations = @voucher.payment_allocations.includes(:settles)
      end

      def new
        @voucher = Voucher.new(voucher_date: Date.current,
                               direction: requested_direction,
                               treasury: Treasury.default_treasury,
                               party_selection: params[:party])
        authorize @voucher
        prefill_from_invoice
        prefill_from_party
        load_form_collections
      end

      def create
        @voucher = Voucher.new(voucher_params)
        authorize @voucher

        if (@over_cap = staff_payment_over_cap)
          load_form_collections
          return render :new, status: :unprocessable_entity
        end

        result = ::Accounting::RecordVoucherService.new(
          direction:    voucher_params[:direction],
          treasury:     Treasury.find_by(id: voucher_params[:treasury_id]),
          user:         current_user,
          amount_cents: @voucher.amount_cents,
          voucher_date: voucher_params[:voucher_date].presence || Date.current,
          counterparty: voucher_params[:counterparty],
          notes:        voucher_params[:notes],
          allocations:  requested_allocations.tap { |list| validate_invoice_allocations!(list) },
          party_type:   @voucher.party_type,
          party_id:     @voucher.party_id
        ).call

        redirect_to admin_accounting_voucher_path(result),
                    notice: t("flash.accounting.voucher_recorded", number: result.number)
      rescue ::Accounting::RecordVoucherService::Error, ActiveRecord::RecordInvalid => e
        @voucher.errors.add(:base, e.message)
        load_form_collections
        render :new, status: :unprocessable_entity
      end

      # Voiding gives the money back and removes the entry, the same way deleting
      # an expense does. A backfilled voucher posted nothing and describes cash
      # that moved before vouchers existed, so voiding one would misrepresent
      # history rather than correct it — the policy refuses those.
      def destroy
        authorize @voucher

        snapshot = {
          number:       @voucher.number,
          direction:    @voucher.direction,
          amount_cents: @voucher.amount_cents,
          date:         @voucher.voucher_date,
          treasury:     @voucher.treasury&.name,
          settles:      @voucher.payment_allocations.map { |a| helpers.settled_label(a.settles) }.compact
        }

        @voucher.void!(user: current_user, reason: :voided_by_user)
        AuditLogEntry.record!(action: "voucher.destroy", record: @voucher, user: current_user,
                              changes_snapshot: snapshot)

        redirect_to admin_accounting_vouchers_path, notice: t("flash.accounting.voucher_voided")
      end

      private

      def set_voucher
        @voucher = Voucher.find(params[:id])
      end

      # A warning, not a rule: paying an employee more than they're owed plus
      # a month's salary is sometimes exactly what the owner means to do. The
      # form comes back once with the figures; ticking the confirmation and
      # submitting again goes through.
      def staff_payment_over_cap
        return unless @voucher.payment? && @voucher.party.is_a?(::User)
        return if params[:confirm_over_cap] == "1"

        employee = @voucher.party
        headroom = employee.staff_payment_headroom_cents
        return if @voucher.amount_cents.to_i <= headroom

        { employee: employee,
          owed_cents: employee.staff_balance_cents,
          salary_cents: employee.monthly_salary_cents.to_i,
          excess_cents: @voucher.amount_cents.to_i - headroom }
      end

      # `direction` comes as a query param on new, and inside the form on a
      # failed create that re-renders it.
      def requested_direction
        direction = params[:direction].presence || params.dig(:voucher, :direction)
        Voucher::DIRECTIONS.include?(direction) ? direction : Voucher::PAYMENT
      end

      # What the voucher settles. One target for now — the table takes many, and
      # will when vouchers absorb supplier and customer payments.
      def requested_allocations
        return oldest_first_allocations if params[:settles] == OLDEST_FIRST

        settles = find_settles_target
        return [] if settles.nil?

        amount = params[:allocation_amount_pounds].presence
        cents  = amount ? (amount.to_d * 100).round : @voucher.amount_cents
        return [] if cents <= 0

        [{ settles: settles, amount_cents: cents }]
      end

      def find_settles_target
        type, id = params[:settles].to_s.split(":", 2)
        return nil if id.blank?

        case type
        when "Expense"         then Expense.find_by(id: id)
        when "Income"          then Income.find_by(id: id)
        when "VendorInvoice"   then VendorInvoice.find_by(id: id)
        when "CustomerInvoice" then CustomerInvoice.find_by(id: id)
        end
      end

      # One amount spread across the party's open invoices, oldest first — what the
      # supplier page's "pay supplier" and the customer statement's "record a
      # payment" used to do, now as a single voucher. A customer may pay ahead:
      # anything left over is allocated to the customer, on their own receivable.
      # A supplier may not, so their AP balance always equals what the open
      # invoices still owe.
      def oldest_first_allocations
        party = @voucher.party
        direction = voucher_params[:direction]

        invoices =
          if party.is_a?(::Supplier) && direction == Voucher::PAYMENT
            ::Accounting::PaySupplierService.open_invoices_for(party)
          elsif party.is_a?(::Customer) && direction == Voucher::RECEIPT
            open_customer_invoices(party)
          else
            raise ::Accounting::RecordVoucherService::Error, t("accounting.vouchers.errors.oldest_first_needs_party")
          end

        remaining = @voucher.amount_cents.to_i
        open_total = invoices.sum(&:balance_due_cents)
        if party.is_a?(::Supplier) && remaining > open_total
          raise ::Accounting::RecordVoucherService::Error,
                t("accounting.vouchers.errors.exceeds_open_invoices", open_total: helpers.format_amount(open_total))
        end

        allocations = invoices.each_with_object([]) do |invoice, list|
          break list if remaining <= 0

          applied = [remaining, invoice.balance_due_cents].min
          remaining -= applied
          list << { settles: invoice, amount_cents: applied }
        end
        allocations << { settles: party, amount_cents: remaining } if remaining.positive?
        allocations
      end

      def open_customer_invoices(customer)
        customer.customer_invoices.outstanding.on_account.order(:invoice_date, :created_at)
                .select { |invoice| invoice.balance_due_cents.positive? }
      end

      # The supplier page and customer statement link in with
      # `party=Supplier:<id>&settles=oldest_first`.
      def prefill_from_party
        return unless params[:settles] == OLDEST_FIRST && params[:party].present?

        @voucher.party_selection = params[:party]
        party = @voucher.party
        invoices = case party
                   when ::Supplier then ::Accounting::PaySupplierService.open_invoices_for(party)
                   when ::Customer then open_customer_invoices(party)
                   else return
                   end
        @selected_settles = OLDEST_FIRST
        @voucher.amount_cents = invoices.sum(&:balance_due_cents)
        @voucher.counterparty = party.is_a?(::Supplier) ? party.name : party.display_name
      end

      # Invoices are paid from here and nowhere else, so the invoice page links in
      # with `settles=VendorInvoice:<id>` (or CustomerInvoice). Start the voucher
      # off with what's left on it and the party it's owed to or by.
      def prefill_from_invoice
        invoice = find_settles_target
        return unless invoice.is_a?(::VendorInvoice) || invoice.is_a?(::CustomerInvoice)

        party = invoice_party(invoice)
        @selected_settles = params[:settles]
        @voucher.amount_cents = [invoice.balance_due_cents, 0].max
        @voucher.party_type = party.class.name
        @voucher.party_id = party.id
        @voucher.counterparty = invoice.is_a?(::VendorInvoice) ? party.name : party.display_name
      end

      def invoice_party(invoice)
        invoice.is_a?(::VendorInvoice) ? invoice.supplier : invoice.customer
      end

      # RecordVoucherService trusts what it settles; an invoice has a balance and a
      # direction of its own, so check them here before any money moves.
      def validate_invoice_allocations!(allocations)
        allocations.each do |allocation|
          invoice = allocation[:settles]
          next unless invoice.is_a?(::VendorInvoice) || invoice.is_a?(::CustomerInvoice)

          expected_direction = invoice.is_a?(::VendorInvoice) ? Voucher::PAYMENT : Voucher::RECEIPT
          open = invoice.is_a?(::VendorInvoice) ? invoice.payable? : payable_customer_invoice?(invoice)

          if voucher_params[:direction] != expected_direction || !open
            raise ::Accounting::RecordVoucherService::Error, t("accounting.vouchers.errors.invoice_not_payable")
          end
          if allocation[:amount_cents] > invoice.balance_due_cents
            raise ::Accounting::RecordVoucherService::Error, t("accounting.vouchers.errors.exceeds_invoice_balance",
                                                               amount: helpers.format_amount(invoice.balance_due_cents))
          end
          if @voucher.party.present? && @voucher.party != invoice_party(invoice)
            raise ::Accounting::RecordVoucherService::Error, t("accounting.vouchers.errors.invoice_party_mismatch")
          end
        end
      end

      # Paid-on-issue invoices settle through their own payment method (cash at
      # confirm, courier remittance, online approval) — only on-account ones are
      # collected by voucher.
      def payable_customer_invoice?(invoice)
        invoice.confirmed? && invoice.on_account? && invoice.balance_due_cents.positive?
      end

      def load_form_collections
        @treasuries = Treasury.active.payable.visible_to(current_user).ordered
        @outstanding = outstanding_targets
        @outstanding_invoices = outstanding_invoices
        @selected_settles ||= params[:settles]
        @party_options = ::Accounting::PartyOptions.for_select
      end

      # Everything still owed, or still owed to us, with what is left on each.
      # An expense that named a treasury was paid as it was recorded and has
      # nothing outstanding, so it never appears here.
      def outstanding_targets
        records = requested_direction == Voucher::RECEIPT ? Income.all : Expense.all
        records
          .where(treasury_id: nil, is_auto_generated: false)
          .includes(:payment_allocations)
          .reject { |record| record.outstanding_cents <= 0 }
          .sort_by { |record| record.public_send(requested_direction == Voucher::RECEIPT ? :income_date : :expense_date) }
      end

      # Open invoices this voucher can pay (supplier) or collect (customer).
      def outstanding_invoices
        if requested_direction == Voucher::RECEIPT
          CustomerInvoice.outstanding.on_account.includes(:customer).order(:invoice_date, :created_at)
                         .select { |invoice| invoice.balance_due_cents.positive? }
        else
          VendorInvoice.posted.outstanding.includes(:supplier).order(:invoice_date, :created_at)
                       .select(&:payable?)
        end
      end

      def voucher_params
        params.require(:voucher).permit(
          :direction, :treasury_id, :voucher_date, :amount_pounds, :counterparty, :notes,
          :party_selection
        )
      end

      def vouchers_csv(scope)
        CSV.generate do |csv|
          csv << [
            t("accounting.vouchers.number"), t("accounting.shared.day"),
            t("accounting.vouchers.direction"), t("accounting.shared.amount"),
            t("accounting.shared.treasury"), t("accounting.vouchers.counterparty"),
            t("accounting.vouchers.settles"), t("accounting.shared.recorded_by"),
            t("accounting.vouchers.status")
          ]
          scope.find_each do |voucher|
            csv << [
              voucher.number,
              voucher.voucher_date,
              t("accounting.vouchers.directions.#{voucher.direction}"),
              helpers.format_amount(voucher.amount_cents),
              voucher.treasury&.name,
              helpers.voucher_party_label(voucher),
              voucher.payment_allocations.map { |a| helpers.settled_label(a.settles) }.compact.join(" · "),
              voucher.user&.name,
              voucher.voided? ? t("accounting.vouchers.voided") : t("accounting.vouchers.live")
            ]
          end
        end
      end
    end
  end
end
