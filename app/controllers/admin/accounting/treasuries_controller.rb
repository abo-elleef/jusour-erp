# frozen_string_literal: true

module Admin
  module Accounting
    class TreasuriesController < BaseController
      before_action :set_treasury, only: %i[show edit update destroy adjust]

      def index
        authorize Treasury
        # Restricted treasuries are only visible to owners/managers.
        visible = Treasury.visible_to(current_user)
        @q = visible.ransack(params[:q])
        @filtered = params[:q].present? && params[:q].to_unsafe_h.values.any?(&:present?)
        base = @q.result
        # Tab counts reflect all visible treasuries per type — switching tabs clears the search.
        @type_counts = visible.group(:treasury_type).count
        @active_type = params[:type].presence
        @active_type = Treasury::TYPES.first unless Treasury::TYPES.include?(@active_type)
        scoped = @active_type ? base.where(treasury_type: @active_type) : base
        @sort = %w[name balance_cents].include?(params[:sort]) ? params[:sort] : nil
        @direction = params[:direction] == "desc" ? "desc" : "asc"
        @treasuries = @sort ? scoped.order(@sort => @direction) : scoped.ordered

        # Point-in-time balance filter.
        # Uses opening_balance_cents + SUM(transactions up to date) — never balance_after_cents,
        # which can be stale when back-dated transactions are inserted without a balance replay.
        @as_of_date = params[:as_of_date].presence&.to_date rescue nil
        if @as_of_date
          ids = @treasuries.pluck(:id)
          txn_sums = TreasuryTransaction
            .where(treasury_id: ids)
            .where(occurred_on: ..@as_of_date)
            .group(:treasury_id)
            .sum(:amount_cents)
          opening = @treasuries.pluck(:id, :opening_balance_cents).to_h
          @as_of_balances = ids.index_with { |id| opening[id].to_i + txn_sums[id].to_i }
          @filter_total_cents = @as_of_balances.values.sum
        else
          @filter_total_cents = scoped.sum(:balance_cents)
        end
      end

      def show
        authorize @treasury
        parse_date_range
        @group_by_day = params[:group_by] == "day"
        txn_scope = @treasury.treasury_transactions.on_date_range(@start_date, @end_date)
        @total_count    = txn_scope.count
        @active_count   = txn_scope.where("amount_cents > 0").count
        @reversed_count = txn_scope.where("amount_cents < 0").count
        @count_labels   = {
          total:    t("accounting.treasuries.stats_total"),
          active:   t("accounting.treasuries.stats_in"),
          reversed: t("accounting.treasuries.stats_out")
        }
        in_cents = txn_scope.where("amount_cents > 0").sum(:amount_cents)
        out_cents = txn_scope.where("amount_cents < 0").sum(:amount_cents).abs
        @range_sums = [
          { label: t("accounting.treasuries.stats_in_amount"), cents: in_cents, tone: :success },
          { label: t("accounting.treasuries.stats_out_amount"), cents: out_cents, tone: :danger }
        ]
        listing = @treasury.treasury_transactions
          .includes(:user, :source_record)
          .on_date_range(@start_date, @end_date)
          .recent

        if @group_by_day
          load_week_page(listing)
        else
          @pagy, @transactions = pagy(:offset, listing, limit: 100)
        end

        respond_to do |format|
          format.html
          format.csv do
            all_transactions = @treasury.treasury_transactions
              .includes(:user, :source_record)
              .on_date_range(@start_date, @end_date)
              .recent
            csv_data = build_transactions_csv(all_transactions)
            filename = "#{@treasury.name.parameterize}-#{@start_date}-#{@end_date}.csv"
            send_data csv_data, filename: filename, type: "text/csv; charset=utf-8", disposition: "attachment"
          end
        end
      end

      def new
        @treasury = Treasury.new(active: true)
        authorize @treasury
      end

      def create
        @treasury = Treasury.new(treasury_params)
        authorize @treasury
        @treasury.balance_cents = @treasury.opening_balance_cents

        if @treasury.save
          clear_other_defaults! if @treasury.is_default?
          redirect_to admin_accounting_treasury_path(@treasury), notice: t("flash.accounting.treasury_created")
        else
          render :new, status: :unprocessable_entity
        end
      end

      def edit
        authorize @treasury
      end

      def update
        authorize @treasury
        if @treasury.update(treasury_params)
          clear_other_defaults! if @treasury.is_default?
          redirect_to admin_accounting_treasury_path(@treasury), notice: t("flash.accounting.treasury_updated")
        else
          render :edit, status: :unprocessable_entity
        end
      end

      def destroy
        authorize @treasury
        if @treasury.expenses.exists? || @treasury.incomes.exists? ||
           @treasury.cash_drawer_sessions.exists? || @treasury.outgoing_transfers.exists? ||
           @treasury.incoming_transfers.exists?
          redirect_to admin_accounting_treasuries_path, alert: t("flash.accounting.treasury_in_use")
        else
          @treasury.destroy!
          redirect_to admin_accounting_treasuries_path, notice: t("flash.accounting.treasury_removed")
        end
      end

      def adjust
        authorize @treasury, :update?
        # A supplier AP ledger is derived: its balance is what the open invoices
        # still owe. A free-hand adjustment breaks that identity silently — 23 of
        # them are why the AP ledger and the invoice list drifted apart. Settle an
        # invoice, or raise a credit note.
        if @treasury.supplier_ap?
          redirect_to admin_accounting_treasury_path(@treasury),
            alert: t("flash.accounting.treasury_ap_adjustment_blocked")
          return
        end

        amount_cents = (params[:amount_pounds].to_f * 100).round
        if amount_cents.zero?
          redirect_to admin_accounting_treasury_path(@treasury), alert: t("flash.accounting.treasury_adjustment_invalid")
          return
        end

        ::Accounting::TreasuryLedgerService.new.record_adjustment!(
          treasury: @treasury,
          user: current_user,
          amount_cents: amount_cents,
          description: params[:description].presence || t("accounting.treasuries.manual_adjustment"),
          occurred_on: params[:occurred_on]&.to_date || Date.current
        )
        redirect_to admin_accounting_treasury_path(@treasury), notice: t("flash.accounting.treasury_adjusted")
      end

      private

      # Grouped mode swaps row pagination for week pagination: one page is one
      # business week (Saturday→Friday, per config.beginning_of_week) and the
      # footer steps a whole week at a time. Weeks stay inside the active date
      # range, so the filter above still bounds what is reachable.
      def load_week_page(listing)
        @first_week = @start_date.beginning_of_week
        # A reversed range (end before start) would make the clamp below blow up.
        @last_week  = [@end_date.beginning_of_week, @first_week].max

        requested = safe_date_param(:week)&.beginning_of_week
        # Default to the newest week in range, matching the descending order of
        # the flat list.
        @week_start = requested ? requested.clamp(@first_week, @last_week) : @last_week
        @week_end   = @week_start.end_of_week

        @previous_week = @week_start - 1.week if @week_start > @first_week
        @next_week     = @week_start + 1.week if @week_start < @last_week

        # A first or last week is usually only partly covered by the range; clip
        # it so the day groups never show days the filter excludes.
        rows = listing.where(occurred_on: [@week_start, @start_date].max..[@week_end, @end_date].min).to_a

        @day_groups = rows.group_by(&:occurred_on).sort_by(&:first).reverse.map do |day, day_rows|
          in_cents  = day_rows.sum { |tx| [tx.amount_cents, 0].max }
          out_cents = day_rows.sum { |tx| [tx.amount_cents, 0].min }.abs
          { day: day, rows: day_rows, in_cents: in_cents, out_cents: out_cents, net_cents: in_cents - out_cents }
        end
        @week_in_cents  = @day_groups.sum { |g| g[:in_cents] }
        @week_out_cents = @day_groups.sum { |g| g[:out_cents] }
      end

      def build_transactions_csv(transactions)
        require "csv"
        headers = [
          t("accounting.shared.day"),
          t("accounting.treasuries.transaction_kind"),
          t("accounting.shared.description"),
          t("accounting.treasuries.amount"),
          t("accounting.treasuries.balance_after"),
          t("accounting.treasuries.recorded_by")
        ]
        CSV.generate(headers: true, encoding: "UTF-8") do |csv|
          csv << headers
          transactions.each do |tx|
            sign = tx.inflow? ? "+" : ""
            csv << [
              tx.occurred_on.iso8601,
              t("accounting.treasuries.transaction_kinds.#{tx.kind}", default: tx.kind.humanize),
              helpers.treasury_transaction_description(tx, current_user),
              "#{sign}#{tx.amount_cents / 100.0}",
              (tx.balance_after_cents / 100.0).to_s,
              tx.user.name
            ]
          end
        end
      end

      def set_treasury
        # Accountants/others hitting a restricted treasury's URL get a 404, not a peek.
        @treasury = Treasury.visible_to(current_user).find(params[:id])
      end

      def treasury_params
        attrs = %i[name treasury_type opening_balance_pounds active is_default position notes]
        # Only owners/managers may mark a treasury restricted.
        attrs << :restricted if current_user.owner? || current_user.manager?
        permitted = params.require(:treasury).permit(*attrs)
        # Supplier AP ledgers are managed by the system — their type can never change.
        permitted.delete(:treasury_type) if @treasury&.supplier_ap?
        permitted
      end

      def clear_other_defaults!
        Treasury.where.not(id: @treasury.id).where(is_default: true).update_all(is_default: false)
      end
    end
  end
end
