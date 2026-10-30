# frozen_string_literal: true

module SuperAdmin
  class CompaniesController < BaseController
    before_action :set_company, only: %i[show edit update impersonate]

    def show
      @locations = Location.unscoped.where(company_id: @company.id).order(:name)
      @owners    = User.unscoped.where(company_id: @company.id, role: "owner").order(:name)
      @stats     = company_stats(@company)
      @storefront = Storefront.unscoped_by_company.find_by(company_id: @company.id)
    end

    def new
      @company = Company.new(locale: "ar", timezone: "Africa/Cairo", currency: "EGP")
    end

    def create
      @company = Company.new(company_params)
      @company.feature_overrides = build_feature_overrides
      if @company.save
        redirect_to super_admin_company_path(@company), notice: "Company created."
      else
        render :new, status: :unprocessable_content
      end
    end

    def edit; end

    def update
      @company.assign_attributes(company_params)
      @company.feature_overrides = build_feature_overrides if params.key?(:feature_overrides)
      if @company.save
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
      params.require(:company).permit(:name, :slug, :timezone, :currency, :locale, :active, :business_type)
    end

    # Turn the per-feature Inherit/On/Off selects into the jsonb overrides hash:
    # only features explicitly forced on/off get a key; "inherit" leaves the
    # profile default in charge.
    def build_feature_overrides
      raw = params[:feature_overrides] || {}
      Company::FEATURES.each_with_object({}) do |feature, acc|
        case raw[feature]
        when "on"  then acc[feature] = true
        when "off" then acc[feature] = false
        end
      end
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
