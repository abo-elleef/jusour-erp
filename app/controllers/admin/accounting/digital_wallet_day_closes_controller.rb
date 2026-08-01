# frozen_string_literal: true

module Admin
  module Accounting
    class DigitalWalletDayClosesController < BaseController
      def show
        load_filters
        @day_close = DigitalWalletDayClose.find_by(business_date: @date, location_id: @location&.id)
        @report = ::Accounting::DigitalWalletDayCloseReport.call(
          date: @date,
          day_close: @day_close,
          location: @location
        )
        @treasury_map = PaymentMethodTreasury::SUPPORTED_METHODS.index_with do |method|
          PaymentMethodTreasury.find_by(payment_method: method)&.treasury
        end
      end

      def update
        load_filters
        @day_close = DigitalWalletDayClose.find_or_initialize_by(
          company: Current.company,
          business_date: @date,
          location_id: @location&.id
        )
        @day_close.assign_attributes(
          instapay_statement_cents: pounds_to_cents(params[:instapay_statement]),
          vodafone_cash_statement_cents: pounds_to_cents(params[:vodafone_cash_statement]),
          notes: params[:notes],
          recorded_by: current_user,
          location: @location
        )

        if @day_close.save
          redirect_to admin_accounting_digital_wallet_day_close_path(date: @date, location_id: @location&.id),
                notice: t("flash.accounting.digital_wallet_day_close_saved")
        else
          @report = ::Accounting::DigitalWalletDayCloseReport.call(
            date: @date,
            day_close: @day_close,
            location: @location
          )
          @treasury_map = PaymentMethodTreasury::SUPPORTED_METHODS.index_with do |method|
            PaymentMethodTreasury.find_by(payment_method: method)&.treasury
          end
          flash.now[:alert] = @day_close.errors.full_messages.to_sentence
          render :show, status: :unprocessable_entity
        end
      end

      private

      def load_filters
        @locations = Location.active.branches.ordered
        @location = @locations.find { |l| l.id == params[:location_id] }
        @date = params[:date]&.to_date || BusinessDay.today(location: @location)
      end

      def pounds_to_cents(value)
        (value.to_f * 100).round
      end
    end
  end
end
