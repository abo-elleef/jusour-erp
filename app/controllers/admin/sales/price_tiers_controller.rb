# frozen_string_literal: true

module Admin
  module Sales
    class PriceTiersController < BaseController
      before_action :set_tier, only: %i[edit update destroy]

      def index
        @tiers = PriceTier.ordered
      end

      def new
        @tier = PriceTier.new(active: true)
      end

      def create
        @tier = PriceTier.new(tier_params)
        if @tier.save
          redirect_to admin_sales_price_tiers_path, notice: t("sales.price_tiers.flash.created")
        else
          render :new, status: :unprocessable_entity
        end
      end

      def edit; end

      def update
        if @tier.update(tier_params)
          redirect_to admin_sales_price_tiers_path, notice: t("sales.price_tiers.flash.updated")
        else
          render :edit, status: :unprocessable_entity
        end
      end

      def destroy
        @tier.destroy
        redirect_to admin_sales_price_tiers_path, notice: t("sales.price_tiers.flash.deleted")
      end

      private

      def set_tier
        @tier = PriceTier.find(params[:id])
      end

      def tier_params
        params.require(:price_tier).permit(:name, :discount_percent, :active, :position)
      end
    end
  end
end
