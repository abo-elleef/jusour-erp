# frozen_string_literal: true

module Admin
  class TaxRatesController < BaseController
    before_action :set_tax_rate, only: %i[edit update destroy]

    def new
      @tax_rate = TaxRate.new(active: true, tax_category: "food", rate_percent: 8)
      authorize @tax_rate
    end

    def create
      @tax_rate = TaxRate.new(tax_rate_params)
      authorize @tax_rate
      if @tax_rate.save
        redirect_to admin_settings_path, notice: t("flash.tax_rate.created")
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      authorize @tax_rate
    end

    def update
      authorize @tax_rate
      if @tax_rate.update(tax_rate_params)
        redirect_to admin_settings_path, notice: t("flash.tax_rate.updated")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      authorize @tax_rate
      @tax_rate.destroy!
      redirect_to admin_settings_path, notice: t("flash.tax_rate.removed")
    end

    private

    def set_tax_rate
      @tax_rate = TaxRate.find(params[:id])
    end

    def tax_rate_params
      params.require(:tax_rate).permit(:name, :tax_category, :rate_percent, :active)
    end
  end
end
