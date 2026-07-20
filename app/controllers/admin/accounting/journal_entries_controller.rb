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
        @total_count     = scope.count
        @reversed_count  = scope.where(entry_type: "reversal").count
        @active_count    = @total_count - @reversed_count
        @count_labels    = {
          total:    t("accounting.journal_entries.stats_total"),
          active:   t("accounting.journal_entries.stats_original"),
          reversed: t("accounting.journal_entries.stats_reversals")
        }
        @journal_entries = scope
      end

      def show
        @journal_entry = JournalEntry.includes(:lines, :created_by, :reversal_entry).find(params[:id])
        @audit_entries = AuditLogEntry.where(record_type: "JournalEntry", record_id: @journal_entry.id)
                                      .includes(:user).order(created_at: :asc)
      end

      def reverse
        @journal_entry = JournalEntry.includes(:reversal_entry).find(params[:id])

        unless @journal_entry.manual?
          return redirect_to admin_accounting_journal_entry_path(@journal_entry),
                             alert: t("accounting.journal_entries.flash.cannot_reverse_auto")
        end

        if @journal_entry.reversed?
          return redirect_to admin_accounting_journal_entry_path(@journal_entry),
                             alert: t("accounting.reversal.already_reversed")
        end

        reversal = nil
        ActiveRecord::Base.transaction do
          reversal = ::Accounting::JournalEntryService.record_reversal!(
            original_je: @journal_entry, user: current_user
          )
          sync_je_treasuries!(reversal)
        end

        snapshot = { original: @journal_entry.entry_number, reversal: reversal.entry_number }
        AuditLogEntry.record!(action: "journal_entry.reverse", record: @journal_entry,
                              user: current_user, changes_snapshot: snapshot)
        AuditLogEntry.record!(action: "journal_entry.create", record: reversal,
                              user: current_user, changes_snapshot: snapshot)

        redirect_to admin_accounting_journal_entry_path(reversal),
                    notice: t("accounting.journal_entries.flash.reversed",
                              number: reversal.entry_number)
      rescue ArgumentError => e
        redirect_to admin_accounting_journal_entry_path(@journal_entry), alert: e.message
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
          AuditLogEntry.record!(
            action: "journal_entry.create",
            record: @journal_entry,
            user: current_user,
            changes_snapshot: {
              entry_number: @journal_entry.entry_number,
              date: @journal_entry.date.to_s,
              description: @journal_entry.description,
              lines: @journal_entry.lines.map { |l|
                { account: l.account_name, debit_cents: l.debit_cents, credit_cents: l.credit_cents }
              }
            }
          )
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
