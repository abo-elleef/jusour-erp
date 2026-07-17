# frozen_string_literal: true

module Admin
  module Accounting
    class JournalEntriesController < BaseController
      def index
        parse_date_range

        scope = JournalEntry.includes(:lines, :created_by)
                            .on_date_range(@start_date, @end_date)
                            .ordered

        scope = scope.by_type(params[:entry_type]) if params[:entry_type].present?

        @entry_type      = params[:entry_type]
        @journal_entries = scope
      end

      def show
        @journal_entry = JournalEntry.includes(:lines, :created_by).find(params[:id])
      end

      def destroy
        @journal_entry = JournalEntry.find(params[:id])

        unless @journal_entry.manual?
          redirect_to admin_accounting_journal_entry_path(@journal_entry),
                      alert: t("accounting.journal_entries.flash.cannot_delete_auto")
          return
        end

        ActiveRecord::Base.transaction do
          reverse_je_treasuries!(@journal_entry)
          @journal_entry.destroy!
        end

        redirect_to admin_accounting_journal_entries_path,
                    notice: t("accounting.journal_entries.flash.deleted")
      rescue ActiveRecord::RecordNotDestroyed => e
        redirect_to admin_accounting_journal_entry_path(@journal_entry),
                    alert: e.message
      end

      def new
        @journal_entry = JournalEntry.new(date: Date.current, entry_type: "manual")
        2.times { @journal_entry.lines.build }
        @account_groups = ::Accounting::AccountListService.new.call
      end

      def create
        @journal_entry = JournalEntry.new(journal_entry_params)
        @journal_entry.entry_type    = "manual"
        @journal_entry.created_by    = current_user
        @journal_entry.entry_number  = JournalEntry.next_entry_number(Current.company.id)

        # Decode account info from the encoded option value
        @journal_entry.lines.each { |line| decode_account!(line) }

        saved = false
        ActiveRecord::Base.transaction do
          @journal_entry.save!
          sync_je_treasuries!(@journal_entry)
          saved = true
        end

        if saved
          redirect_to admin_accounting_journal_entry_path(@journal_entry),
                      notice: t("accounting.journal_entries.flash.created")
        else
          @account_groups = ::Accounting::AccountListService.new.call
          render :new, status: :unprocessable_entity
        end
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved
        @account_groups = ::Accounting::AccountListService.new.call
        render :new, status: :unprocessable_entity
      end

      private

      def journal_entry_params
        params.require(:journal_entry).permit(
          :date, :description,
          lines_attributes: %i[account_encoded debit_pounds credit_pounds]
        )
      end

      # The select option value is "kind|id|name|account_type".
      # Decode it and set the proper line attributes.
      def decode_account!(line)
        encoded = line.account_encoded.to_s
        return if encoded.blank?

        kind, id, name, account_type = encoded.split("|", 4)

        line.account_name  = name
        line.account_type  = account_type
        line.treasury_id   = (kind == "treasury") ? id : nil
        line.debit_cents   = to_cents(line.debit_pounds)
        line.credit_cents  = to_cents(line.credit_pounds)
        line.account_code  = resolve_code(kind, id, account_type, name)
      end

      def to_cents(pounds)
        (pounds.to_f * 100).round
      end

      # For each JE line that targets a treasury, create a TreasuryTransaction so
      # the treasury balance stays in sync with the double-entry ledger.
      # Amount direction convention (matches TreasuryLedgerService):
      #   asset treasury  → debit_cents - credit_cents  (DR = money in, CR = money out)
      #   liability (AP)  → credit_cents - debit_cents  (CR = more owed, DR = payment)
      def sync_je_treasuries!(je)
        je.lines.each do |line|
          next if line.treasury_id.blank?

          treasury = Treasury.lock.find(line.treasury_id)
          amount_cents = if treasury.treasury_type == "supplier_ap"
                           line.credit_cents - line.debit_cents
                         else
                           line.debit_cents - line.credit_cents
                         end
          next if amount_cents.zero?

          treasury.apply_balance_delta!(amount_cents)
          TreasuryTransaction.create!(
            treasury:           treasury,
            user:               je.created_by,
            amount_cents:       amount_cents,
            kind:               "journal_entry",
            description:        je.description,
            occurred_on:        je.date,
            source_record:      je,
            balance_after_cents: treasury.balance_cents
          )
        end
      end

      # Undo treasury movements created by sync_je_treasuries! when a manual JE
      # is deleted. Each TreasuryTransaction sourced on the JE is destroyed and
      # the treasury balance is reversed by the same amount.
      def reverse_je_treasuries!(je)
        TreasuryTransaction
          .where(source_record_type: "JournalEntry", source_record_id: je.id)
          .find_each do |txn|
            txn.treasury.with_lock do
              txn.treasury.apply_balance_delta!(-txn.amount_cents)
              txn.destroy!
            end
          end
      end

      def resolve_code(kind, id, account_type, name)
        case kind
        when "treasury"
          t = Treasury.find_by(id: id)
          return 1500 unless t
          base = ::Accounting::JournalEntryService::TREASURY_TYPE_BASE.fetch(t.treasury_type, 1500)
          siblings = Treasury.unscoped.where(company_id: t.company_id,
                                             treasury_type: t.treasury_type).order(:position, :name)
          base + siblings.pluck(:id).index(t.id).to_i + 1
        when "equity"
          3001
        when "income_category"
          siblings = IncomeCategory.order(:name).pluck(:id)
          4001 + siblings.index(id).to_i
        when "expense_category"
          siblings = ExpenseCategory.order(:name).pluck(:id)
          5001 + siblings.index(id).to_i
        when "fixed_expense"
          id.to_i
        when "partner"
          Partner.find_by(id: id)&.account_code || 3199
        when "loan"
          Loan.find_by(id: id)&.account_code || 2199
        else
          5999
        end
      end
    end
  end
end
