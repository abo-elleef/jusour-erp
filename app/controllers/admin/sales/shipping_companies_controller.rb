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

      def show; end

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
    end
  end
end
