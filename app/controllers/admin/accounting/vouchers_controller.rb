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
      before_action :set_voucher, only: %i[show destroy]

      def index
        parse_date_range(default_start: Date.current.beginning_of_month)

        @q = Voucher.ransack(params[:q])
        scope = @q.result.includes(:treasury, :user, payment_allocations: :settles)
        scope = scope.on_date_range(@start_date, @end_date)
        scope = scope.where(direction: params[:direction]) if Voucher::DIRECTIONS.include?(params[:direction])
        scope = scope.where(treasury_id: params[:treasury_id]) if params[:treasury_id].present?

        totals = scope.unscope(:includes)
        @received_cents = totals.receipts.sum(:amount_cents)
        @paid_cents     = totals.payments.sum(:amount_cents)
        @total_count    = totals.count

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
                               treasury: Treasury.default_treasury)
        authorize @voucher
        load_form_collections
      end

      def create
        @voucher = Voucher.new(voucher_params)
        authorize @voucher

        result = ::Accounting::RecordVoucherService.new(
          direction:    voucher_params[:direction],
          treasury:     Treasury.find_by(id: voucher_params[:treasury_id]),
          user:         current_user,
          amount_cents: @voucher.amount_cents,
          voucher_date: voucher_params[:voucher_date].presence || Date.current,
          counterparty: voucher_params[:counterparty],
          notes:        voucher_params[:notes],
          allocations:  requested_allocations
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

        @voucher.destroy!
        AuditLogEntry.record!(action: "voucher.destroy", record: @voucher, user: current_user,
                              changes_snapshot: snapshot)

        redirect_to admin_accounting_vouchers_path, notice: t("flash.accounting.voucher_voided")
      end

      private

      def set_voucher
        @voucher = Voucher.find(params[:id])
      end

      def requested_direction
        Voucher::DIRECTIONS.include?(params[:direction]) ? params[:direction] : Voucher::PAYMENT
      end

      # What the voucher settles. One target for now — the table takes many, and
      # will when vouchers absorb supplier and customer payments.
      def requested_allocations
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
        when "Expense" then Expense.find_by(id: id)
        when "Income"  then Income.find_by(id: id)
        end
      end

      def load_form_collections
        @treasuries = Treasury.active.payable.visible_to(current_user).ordered
        @outstanding = outstanding_targets
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

      def voucher_params
        params.require(:voucher).permit(
          :direction, :treasury_id, :voucher_date, :amount_pounds, :counterparty, :notes
        )
      end

      def vouchers_csv(scope)
        CSV.generate do |csv|
          csv << [
            t("accounting.vouchers.number"), t("accounting.shared.day"),
            t("accounting.vouchers.direction"), t("accounting.shared.amount"),
            t("accounting.shared.treasury"), t("accounting.vouchers.counterparty"),
            t("accounting.vouchers.settles"), t("accounting.shared.recorded_by")
          ]
          scope.find_each do |voucher|
            csv << [
              voucher.number,
              voucher.voucher_date,
              t("accounting.vouchers.directions.#{voucher.direction}"),
              helpers.format_amount(voucher.amount_cents),
              voucher.treasury&.name,
              voucher.counterparty,
              voucher.payment_allocations.map { |a| helpers.settled_label(a.settles) }.compact.join(" · "),
              voucher.user&.name
            ]
          end
        end
      end
    end
  end
end
