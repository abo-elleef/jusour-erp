# frozen_string_literal: true

module Admin
  module Accounting
    class FixedAssetsController < BaseController
      before_action :set_fixed_asset,
        only: %i[show edit update destroy dispose record_payment]

      def index
        @fixed_assets = FixedAsset.ordered.includes(:location, :recorded_by)
        @total_purchase_cents = @fixed_assets.sum(:purchase_price_cents)
        @total_current_value_cents = @fixed_assets.sum(:current_value_cents)
        @by_type = @fixed_assets.active.group_by(&:asset_type)
        @show_disposed = params[:show_disposed] == "1"
        @fixed_assets = @show_disposed ? @fixed_assets : @fixed_assets.active
      end

      def show
        @payments = @fixed_asset.fixed_asset_payments.includes(:treasury, :user).ordered
        @payment = FixedAssetPayment.new(payment_date: Date.current)
        @treasuries = payable_treasuries
        @journal_entry = JournalEntry.for_source(@fixed_asset).includes(:lines).first
      end

      def new
        @fixed_asset = FixedAsset.new(
          purchase_date: Date.current,
          active: true,
          recorded_by: current_user
        )
        load_form_data
      end

      # Buying the machine IS the accounting event: cash leaves here when paid
      # outright, and the journal debits the asset account either way. No separate
      # Expense, which is what used to double-count it in the cash flow.
      def create
        @fixed_asset = FixedAsset.new(fixed_asset_params.merge(recorded_by: current_user))

        if @fixed_asset.save
          ::Accounting::FixedAssetLedgerService.record_purchase!(asset: @fixed_asset, user: current_user)
          redirect_to admin_accounting_fixed_asset_path(@fixed_asset),
            notice: t("accounting.fixed_assets.flash.created")
        else
          load_form_data
          render :new, status: :unprocessable_entity
        end
      rescue ::Accounting::FixedAssetLedgerService::Error => e
        @fixed_asset.destroy if @fixed_asset.persisted?
        @fixed_asset.errors.add(:base, e.message)
        load_form_data
        render :new, status: :unprocessable_entity
      end

      def record_payment
        unless @fixed_asset.on_credit?
          redirect_to admin_accounting_fixed_asset_path(@fixed_asset),
            alert: t("accounting.fixed_assets.errors.not_on_credit")
          return
        end

        @payment = @fixed_asset.fixed_asset_payments.new(
          payment_params.merge(user: current_user, company: @fixed_asset.company)
        )

        if @payment.save
          ::Accounting::FixedAssetLedgerService.record_payment!(payment: @payment, user: current_user)
          redirect_to admin_accounting_fixed_asset_path(@fixed_asset),
            notice: t("accounting.fixed_assets.flash.payment_recorded")
        else
          redirect_to admin_accounting_fixed_asset_path(@fixed_asset),
            alert: @payment.errors.full_messages.to_sentence
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
        ::Accounting::FixedAssetLedgerService.reverse_asset!(asset: @fixed_asset)
        redirect_to admin_accounting_fixed_assets_path,
          notice: t("accounting.fixed_assets.flash.deleted")
      rescue ::Accounting::FixedAssetLedgerService::Error => e
        redirect_to admin_accounting_fixed_asset_path(@fixed_asset), alert: e.message
      end

      private

      def set_fixed_asset
        @fixed_asset = FixedAsset.find(params[:id])
      end

      def load_form_data
        @locations = Location.active.ordered
        @treasuries = payable_treasuries
      end

      def payable_treasuries
        Treasury.active.payable.visible_to(current_user).ordered
      end

      def payment_params
        params.require(:fixed_asset_payment).permit(:amount_pounds, :payment_date, :treasury_id, :notes)
      end

      def fixed_asset_params
        params.require(:fixed_asset).permit(
          :name, :asset_type, :purchase_date, :purchase_price_pounds,
          :current_value_pounds, :useful_life_years, :serial_number,
          :notes, :location_id, :paid_from_treasury_id, :on_credit, :supplier_name
        )
      end
    end
  end
end
