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
        # Aggregate balance of the treasuries matching the active type filter.
        @filter_total_cents = scoped.sum(:balance_cents)
      end

      def show
        authorize @treasury
        parse_date_range
        @transactions = @treasury.treasury_transactions
          .includes(:user)
          .on_date_range(@start_date, @end_date)
          .recent
          .limit(200)

        respond_to do |format|
          format.html
          format.csv do
            csv_data = build_transactions_csv(@transactions)
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
