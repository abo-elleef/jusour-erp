# frozen_string_literal: true

module Admin
  module Accounting
    class FixedAssetsController < BaseController
      before_action :set_fixed_asset, only: %i[show edit update destroy dispose]

      def index
        @fixed_assets = FixedAsset.ordered.includes(:location, :recorded_by)
        @total_purchase_cents = @fixed_assets.sum(:purchase_price_cents)
        @total_current_value_cents = @fixed_assets.sum(:current_value_cents)
        @by_type = @fixed_assets.active.group_by(&:asset_type)
        @show_disposed = params[:show_disposed] == "1"
        @fixed_assets = @show_disposed ? @fixed_assets : @fixed_assets.active
      end

      def show; end

      def new
        @fixed_asset = FixedAsset.new(
          purchase_date: Date.current,
          active: true,
          recorded_by: current_user
        )
        load_form_data
      end

      def create
        @fixed_asset = FixedAsset.new(fixed_asset_params.merge(recorded_by: current_user))
        if @fixed_asset.save
          redirect_to admin_accounting_fixed_asset_path(@fixed_asset),
            notice: t("accounting.fixed_assets.flash.created")
        else
          load_form_data
          render :new, status: :unprocessable_entity
        end
      end

      def edit
        load_form_data
      end

      def update
        if @fixed_asset.update(fixed_asset_params)
          redirect_to admin_accounting_fixed_asset_path(@fixed_asset),
            notice: t("accounting.fixed_assets.flash.updated")
        else
          load_form_data
          render :edit, status: :unprocessable_entity
        end
      end

      def dispose
        @fixed_asset.update!(active: false, current_value_cents: 0)
        redirect_to admin_accounting_fixed_assets_path,
          notice: t("accounting.fixed_assets.flash.disposed", name: @fixed_asset.name)
      end

      def destroy
        @fixed_asset.destroy!
        redirect_to admin_accounting_fixed_assets_path,
          notice: t("accounting.fixed_assets.flash.deleted")
      end

      private

      def set_fixed_asset
        @fixed_asset = FixedAsset.find(params[:id])
      end

      def load_form_data
        @locations = Location.active.ordered
      end

      def fixed_asset_params
        params.require(:fixed_asset).permit(
          :name, :asset_type, :purchase_date, :purchase_price_pounds,
          :current_value_pounds, :useful_life_years, :serial_number,
          :notes, :location_id
        )
      end
    end
  end
end
