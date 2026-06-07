# frozen_string_literal: true

module Admin
  module Accounting
    class TreasuryTransfersController < BaseController
      def new
        @transfer = TreasuryTransfer.new(
          occurred_on: Date.current,
          from_treasury_id: params[:from_treasury_id]
        )
        authorize @transfer
        @treasuries = Treasury.active.payable.ordered
      end

      def create
        @transfer = TreasuryTransfer.new(transfer_params.merge(user: current_user))
        authorize @transfer

        if @transfer.valid?
          ::Accounting::TreasuryLedgerService.create_transfer!(@transfer)
          redirect_to admin_accounting_treasury_path(@transfer.from_treasury),
            notice: t("flash.accounting.treasury_transfer_recorded")
        else
          @treasuries = Treasury.active.payable.ordered
          render :new, status: :unprocessable_entity
        end
      end

      private

      def transfer_params
        params.require(:treasury_transfer).permit(
          :from_treasury_id, :to_treasury_id, :amount_cents, :description, :occurred_on
        )
      end
    end
  end
end
