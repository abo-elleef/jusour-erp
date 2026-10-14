# frozen_string_literal: true

module Admin
  module Sales
    class ShippingCompaniesController < BaseController
      before_action :set_shipping_company, only: %i[show edit update destroy]

      def index
        @status = params[:status].presence_in(%w[active inactive])
        @q = ShippingCompany.ransack(params[:q])
        @sort = parse_index_sort_param
        @direction = parse_index_sort_direction_param
        @filtered = (params[:q].present? && params[:q].to_unsafe_h.values.any?(&:present?)) || @status.present?

        scope = @q.result
        scope = scope.where(active: @status == "active") if @status

        scope = if @sort == "balance"
                  scope.left_joins(:ar_treasury)
                       .order(Arel.sql("COALESCE(treasuries.balance_cents, 0) #{@direction}"), name: :asc)
                else
                  scope.order(@sort => @direction, name: :asc)
                end

        @pagy, @shipping_companies = pagy(:offset, scope, limit: 25)
      end

      def show
        treasury = @shipping_company.ar_treasury
        base = treasury ? treasury.treasury_transactions.includes(:user, :source_record) : TreasuryTransaction.none
        @pagy, @transactions = pagy(:offset, base.recent, limit: 50)

        respond_to do |format|
          format.html
          format.csv do
            # Statement order: oldest first, ending at today's balance — the
            # order a printed/shared statement is read in, not the on-screen
            # most-recent-first list above.
            csv_data = build_statement_csv(base.order(occurred_on: :asc, created_at: :asc))
            filename = "#{@shipping_company.name.parameterize}-statement.csv"
            send_data csv_data, filename: filename, type: "text/csv; charset=utf-8", disposition: "attachment"
          end
        end
      end

      def new
        @shipping_company = ShippingCompany.new(active: true)
      end

      def create
        @shipping_company = ShippingCompany.new(shipping_company_params)
        if @shipping_company.save
          redirect_to admin_sales_shipping_companies_path,
            notice: t("sales.shipping_companies.flash.created")
        else
          render :new, status: :unprocessable_entity
        end
      end

      def edit; end

      def update
        if @shipping_company.update(shipping_company_params)
          redirect_to admin_sales_shipping_companies_path,
            notice: t("sales.shipping_companies.flash.updated")
        else
          render :edit, status: :unprocessable_entity
        end
      end

      def destroy
        unless @shipping_company.deletable?
          redirect_to admin_sales_shipping_companies_path, alert: t("sales.shipping_companies.flash.cannot_delete")
          return
        end

        ActiveRecord::Base.transaction do
          treasury = @shipping_company.ar_treasury
          @shipping_company.destroy!
          treasury&.destroy!
        end
        redirect_to admin_sales_shipping_companies_path, notice: t("sales.shipping_companies.flash.deleted")
      end

      private

      def set_shipping_company
        @shipping_company = ShippingCompany.find(params[:id])
      end

      def shipping_company_params
        params.require(:shipping_company).permit(:name, :phone, :notes, :active)
      end

      def parse_index_sort_param
        sort = params[:sort].to_s
        ShippingCompany::INDEX_SORTABLE_COLUMNS.include?(sort) ? sort : ShippingCompany::INDEX_DEFAULT_SORT
      end

      def parse_index_sort_direction_param
        params[:dir].to_s == "desc" ? "desc" : ShippingCompany::INDEX_DEFAULT_SORT_DIRECTION
      end

      # Evidence the shipping company's balance can be handed to them directly —
      # every transaction that built it, with the originating invoice visible.
      def build_statement_csv(transactions)
        require "csv"
        headers = [
          t("accounting.shared.day"),
          t("accounting.treasuries.transaction_kind"),
          t("accounting.shared.description"),
          t("accounting.treasuries.amount"),
          t("accounting.treasuries.balance_after")
        ]
        CSV.generate(headers: true, encoding: "UTF-8") do |csv|
          csv << headers
          transactions.each do |tx|
            sign = tx.inflow? ? "+" : ""
            csv << [
              tx.occurred_on.iso8601,
              helpers.accounting_treasury_transaction_kind(tx.kind),
              helpers.treasury_transaction_description(tx, current_user),
              "#{sign}#{tx.amount_cents / 100.0}",
              (tx.balance_after_cents / 100.0).to_s
            ]
          end
        end
      end
    end
  end
end
