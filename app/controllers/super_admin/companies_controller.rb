# frozen_string_literal: true

module SuperAdmin
  class CompaniesController < BaseController
    before_action :set_company, only: %i[show edit update impersonate]

    def show
      @locations = Location.unscoped.where(company_id: @company.id).order(:name)
      @owners    = User.unscoped.where(company_id: @company.id, role: "owner").order(:name)
      @stats     = company_stats(@company)
    end

    def new
      @company = Company.new(locale: "ar", timezone: "Africa/Cairo", currency: "EGP")
    end

    def create
      @company = Company.new(company_params)
      if @company.save
        redirect_to super_admin_company_path(@company), notice: "Company created."
      else
        render :new, status: :unprocessable_content
      end
    end

    def edit; end

    def update
      if @company.update(company_params)
        redirect_to super_admin_company_path(@company), notice: "Company updated."
      else
        render :edit, status: :unprocessable_content
      end
    end

    def impersonate
      owner = User.unscoped.where(company_id: @company.id, role: "owner").first
      unless owner
        redirect_to super_admin_company_path(@company), alert: "No owner account found for this company."
        return
      end

      sign_in(:user, owner)
      redirect_to admin_root_path
    end

    private

    def set_company
      @company = Company.unscoped.find(params[:id])
    end

    def company_params
      params.require(:company).permit(:name, :slug, :timezone, :currency, :locale, :active)
    end

    def company_stats(company)
      Company.unscoped
        .joins("LEFT JOIN orders ON orders.company_id = companies.id AND orders.status NOT IN ('draft', 'voided')")
        .where("companies.id = ?", company.id)
        .group("companies.id")
        .select(
          "COUNT(DISTINCT orders.id) AS orders_count",
          "COALESCE(SUM(orders.total_cents), 0) AS revenue_cents"
        )
        .first
    end
  end
end
