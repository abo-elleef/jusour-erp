# frozen_string_literal: true

module Admin
  module Accounting
    class PartnersController < BaseController
      before_action :set_partner, only: %i[show edit update]

      def index
        @partners = Partner.ordered
        @total_ownership = @partners.active.sum(:ownership_percentage)
      end

      def show
        @lines = JournalEntryLine.joins(:journal_entry)
                                 .where(journal_entries: { company_id: Current.company.id })
                                 .where(account_code: @partner.account_code)
                                 .includes(:journal_entry)
                                 .order("journal_entries.date DESC, journal_entries.entry_number DESC")
        @balance_cents = @partner.balance_cents
      end

      def new
        @partner = Partner.new
      end

      def create
        @partner = Partner.new(partner_params)
        if @partner.save
          redirect_to admin_accounting_partner_path(@partner),
                      notice: t("accounting.partners.flash.created")
        else
          render :new, status: :unprocessable_entity
        end
      end

      def edit; end

      def update
        if @partner.update(partner_params)
          redirect_to admin_accounting_partner_path(@partner),
                      notice: t("accounting.partners.flash.updated")
        else
          render :edit, status: :unprocessable_entity
        end
      end

      # GET /partners/:id/advance/new
      def new_advance
        @partner = Partner.find(params[:id])
        @treasuries = Treasury.active.where.not(treasury_type: "supplier_ap").order(:position, :name)
      end

      # POST /partners/:id/advance
      def create_advance
        @partner = Partner.find(params[:id])
        @treasuries = Treasury.active.where.not(treasury_type: "supplier_ap").order(:position, :name)

        treasury = Treasury.find(params[:treasury_id])
        amount_cents = (params[:amount].to_f * 100).round
        date = Date.parse(params[:date])
        description = params[:description].presence || t("accounting.partners.advance.default_description", name: @partner.name)

        if amount_cents <= 0
          @error = t("accounting.partners.advance.amount_required")
          return render :new_advance, status: :unprocessable_entity
        end

        ActiveRecord::Base.transaction do
          je = ::Accounting::JournalEntryService.record_partner_advance!(
            partner: @partner,
            treasury: treasury,
            amount_cents: amount_cents,
            date: date,
            description: description,
            user: current_user
          )
          sync_je_treasuries!(je)
        end

        redirect_to admin_accounting_partner_path(@partner),
                    notice: t("accounting.partners.flash.advance_recorded")
      end

      # GET /accounting/profit_distribution/new
      def new_profit_distribution
        @partners = Partner.active.ordered
        @total_ownership = @partners.sum(:ownership_percentage)
      end

      # POST /accounting/profit_distribution
      def create_profit_distribution
        @partners = Partner.active.ordered
        @total_ownership = @partners.sum(:ownership_percentage)

        total_cents = (params[:total_amount].to_f * 100).round
        date = Date.parse(params[:date])
        description = params[:description].presence || t("accounting.partners.profit.default_description")

        if total_cents <= 0
          @error = t("accounting.partners.profit.amount_required")
          return render :new_profit_distribution, status: :unprocessable_entity
        end

        ::Accounting::JournalEntryService.distribute_profit!(
          partners: @partners,
          total_cents: total_cents,
          date: date,
          description: description,
          user: current_user
        )

        redirect_to admin_accounting_partners_path,
                    notice: t("accounting.partners.flash.profit_distributed")
      end

      private

      def set_partner
        @partner = Partner.find(params[:id])
      end

      def partner_params
        params.require(:partner).permit(:name, :ownership_percentage, :active, :notes)
      end
    end
  end
end
