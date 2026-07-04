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
        @treasuries = Treasury.active.payable.visible_to(current_user).ordered
      end

      def create
        @transfer = TreasuryTransfer.new(transfer_params.merge(user: current_user))
        authorize @transfer

        # A user who can't see a restricted treasury can't move money to/from it either.
        if touches_hidden_treasury?
          raise ActiveRecord::RecordNotFound
        end

        if @transfer.valid?
          ::Accounting::TreasuryLedgerService.create_transfer!(@transfer)
          redirect_to admin_accounting_treasury_path(@transfer.from_treasury),
            notice: t("flash.accounting.treasury_transfer_recorded")
        else
          @treasuries = Treasury.active.payable.visible_to(current_user).ordered
          render :new, status: :unprocessable_entity
        end
      end

      private

      def touches_hidden_treasury?
        return false if current_user.owner? || current_user.manager?

        [@transfer.from_treasury, @transfer.to_treasury].compact.any?(&:restricted?)
      end

      def transfer_params
        params.require(:treasury_transfer).permit(
          :from_treasury_id, :to_treasury_id, :amount_pounds, :description, :occurred_on
        )
      end
    end
  end
end
