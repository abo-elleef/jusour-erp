# frozen_string_literal: true

module Admin
  module Accounting
    class LoansController < BaseController
      before_action :set_loan, only: %i[show edit update
                                        new_disbursement create_disbursement
                                        new_opening_balance create_opening_balance
                                        new_repayment    create_repayment
                                        new_interest     create_interest]

      def index
        @loans = Loan.ordered
      end

      def show
        @lines = JournalEntryLine.joins(:journal_entry)
                                 .where(journal_entries: { company_id: Current.company.id })
                                 .where(account_code: @loan.account_code)
                                 .includes(:journal_entry)
                                 .order("journal_entries.date DESC, journal_entries.entry_number DESC")
        @outstanding_cents = @loan.outstanding_balance_cents
      end

      def new
        @loan = Loan.new
      end

      def create
        @loan = Loan.new(loan_params)
        if @loan.save
          redirect_to admin_accounting_loan_path(@loan),
                      notice: t("accounting.loans.flash.created")
        else
          render :new, status: :unprocessable_entity
        end
      end

      def edit; end

      def update
        if @loan.update(loan_params)
          redirect_to admin_accounting_loan_path(@loan),
                      notice: t("accounting.loans.flash.updated")
        else
          render :edit, status: :unprocessable_entity
        end
      end

      # GET /loans/:id/disbursement/new
      def new_disbursement
        @treasuries = active_treasuries
      end

      # POST /loans/:id/disbursement
      def create_disbursement
        @treasuries  = active_treasuries
        treasury     = Treasury.find(params[:treasury_id])
        amount_cents = (params[:amount].to_f * 100).round
        date         = Date.parse(params[:date])
        description  = params[:description].presence ||
                       t("accounting.loans.disbursement.default_description", name: @loan.name)

        if amount_cents <= 0
          @error = t("accounting.loans.errors.amount_required")
          return render :new_disbursement, status: :unprocessable_entity
        end

        ActiveRecord::Base.transaction do
          je = ::Accounting::JournalEntryService.record_loan_disbursement!(
            loan: @loan, treasury: treasury, amount_cents: amount_cents,
            date: date, description: description, user: current_user
          )
          sync_je_treasuries!(je)
        end
        redirect_to admin_accounting_loan_path(@loan),
                    notice: t("accounting.loans.flash.disbursement_recorded")
      end

      # GET /loans/:id/opening_balance/new
      #
      # For a loan whose cash arrived long ago and is already inside the
      # treasury's current balance — seeds the liability against Retained
      # Earnings instead of a disbursement, so nothing here inflates cash a
      # second time. Only offered while the loan's account has never posted
      # anything; once a disbursement, opening balance, or repayment exists,
      # this would double it up.
      def new_opening_balance
        return blocked_opening_balance unless @loan.ledger_untouched?
      end

      # POST /loans/:id/opening_balance
      def create_opening_balance
        return blocked_opening_balance unless @loan.ledger_untouched?

        amount_cents = (params[:amount].to_f * 100).round
        date         = Date.parse(params[:date])
        description  = params[:description].presence

        if amount_cents <= 0
          @error = t("accounting.loans.errors.amount_required")
          return render :new_opening_balance, status: :unprocessable_entity
        end

        ::Accounting::JournalEntryService.record_loan_opening_balance!(
          loan: @loan, amount_cents: amount_cents, date: date, description: description, user: current_user
        )
        redirect_to admin_accounting_loan_path(@loan),
                    notice: t("accounting.loans.flash.opening_balance_recorded")
      end

      # GET /loans/:id/repayment/new
      def new_repayment
        @treasuries = active_treasuries
      end

      # POST /loans/:id/repayment
      def create_repayment
        @treasuries  = active_treasuries
        treasury     = Treasury.find(params[:treasury_id])
        amount_cents = (params[:amount].to_f * 100).round
        date         = Date.parse(params[:date])
        description  = params[:description].presence ||
                       t("accounting.loans.repayment.default_description", name: @loan.name)

        if amount_cents <= 0
          @error = t("accounting.loans.errors.amount_required")
          return render :new_repayment, status: :unprocessable_entity
        end

        ActiveRecord::Base.transaction do
          je = ::Accounting::JournalEntryService.record_loan_repayment!(
            loan: @loan, treasury: treasury, amount_cents: amount_cents,
            date: date, description: description, user: current_user
          )
          sync_je_treasuries!(je)
        end
        redirect_to admin_accounting_loan_path(@loan),
                    notice: t("accounting.loans.flash.repayment_recorded")
      end

      # GET /loans/:id/interest/new
      def new_interest
        @treasuries = active_treasuries
      end

      # POST /loans/:id/interest
      def create_interest
        @treasuries  = active_treasuries
        treasury     = Treasury.find(params[:treasury_id])
        amount_cents = (params[:amount].to_f * 100).round
        date         = Date.parse(params[:date])
        description  = params[:description].presence ||
                       t("accounting.loans.interest.default_description", name: @loan.name)

        if amount_cents <= 0
          @error = t("accounting.loans.errors.amount_required")
          return render :new_interest, status: :unprocessable_entity
        end

        ActiveRecord::Base.transaction do
          je = ::Accounting::JournalEntryService.record_loan_interest!(
            loan: @loan, treasury: treasury, amount_cents: amount_cents,
            date: date, description: description, user: current_user
          )
          sync_je_treasuries!(je)
        end
        redirect_to admin_accounting_loan_path(@loan),
                    notice: t("accounting.loans.flash.interest_recorded")
      end

      private

      def blocked_opening_balance
        redirect_to admin_accounting_loan_path(@loan),
                    alert: t("accounting.loans.errors.opening_balance_blocked")
      end

      def set_loan
        @loan = Loan.find(params[:id])
      end

      def loan_params
        params.require(:loan).permit(
          :name, :loan_type, :principal_cents, :interest_rate,
          :disbursement_date, :due_date, :active, :notes, :installments_total
        )
      end

      def active_treasuries
        Treasury.active.where.not(treasury_type: "supplier_ap").order(:position, :name)
      end
    end
  end
end
