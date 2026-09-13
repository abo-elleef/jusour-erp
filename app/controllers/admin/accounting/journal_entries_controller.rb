# frozen_string_literal: true

require "csv"

module Admin
  module Accounting
    class JournalEntriesController < BaseController
      SORT_COLUMNS = %w[date debits credits].freeze

      def index
        parse_date_range

        scope = JournalEntry.includes(:lines, :created_by)
                            .on_date_range(@start_date, @end_date)
                            .ordered

        scope = scope.by_type(params[:entry_type]) if params[:entry_type].present?

        @account_code = params[:account_code].presence
        if @account_code
          scope = scope.where(
            id: JournalEntryLine.where(account_code: @account_code).select(:journal_entry_id)
          )
        end

        @entry_type   = params[:entry_type]
        @total_count  = scope.count
        @count_labels = { total: t("accounting.journal_entries.stats_total") }

        @sort      = SORT_COLUMNS.include?(params[:sort]) ? params[:sort] : "date"
        @direction = params[:dir] == "asc" ? "asc" : "desc"
        entries    = sort_entries(scope.to_a)

        respond_to do |format|
          format.html { @journal_entries = entries }
          format.csv  { send_journal_entries_csv(entries) }
        end
      end

      def show
        @journal_entry = JournalEntry.includes(:lines, :created_by).find(params[:id])
        @audit_entries = AuditLogEntry.where(record_type: "JournalEntry", record_id: @journal_entry.id)
                                      .includes(:user).order(created_at: :asc)
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
                { account: l.account_name, debit_cents: l.debit_cents, credit_cents: l.credit_cents, notes: l.notes }
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

      # Sorted in Ruby rather than SQL: debits and credits are summed from the
      # entry's lines, which are already loaded for the table and its totals, so
      # a GROUP BY would buy nothing and make the two orderings behave
      # differently. The page is a single date range, not the whole ledger.
      def sort_entries(entries)
        sorted = case @sort
                 when "debits"  then entries.sort_by { |e| [e.total_debits_cents, e.date, e.entry_number] }
                 when "credits" then entries.sort_by { |e| [e.total_credits_cents, e.date, e.entry_number] }
                 else entries.sort_by { |e| [e.date, e.entry_number] }
                 end
        @direction == "desc" ? sorted.reverse : sorted
      end

      # Takes the already-sorted, already-eager-loaded entries so the export lands
      # in the same order as the table the reader is looking at.
      def send_journal_entries_csv(entries)
        # CSV.generate appends to the string it is given, and this file is
        # frozen_string_literal, so the BOM has to be an unfrozen copy — without
        # the +, every export raised IOError: not opened for writing.
        csv = CSV.generate(+"\xEF\xBB\xBF") do |out|
          out << [
            t("accounting.journal_entries.csv.entry_number"),
            t("accounting.journal_entries.csv.date"),
            t("accounting.journal_entries.csv.description"),
            t("accounting.journal_entries.csv.account_code"),
            t("accounting.journal_entries.csv.account_name"),
            t("accounting.journal_entries.csv.debit"),
            t("accounting.journal_entries.csv.credit"),
            t("accounting.journal_entries.csv.entry_type"),
            t("accounting.journal_entries.csv.created_by")
          ]
          entries.each do |entry|
            entry.lines.each do |line|
              next if @account_code && line.account_code.to_s != @account_code.to_s

              out << [
                entry.entry_number,
                entry.date.iso8601,
                entry.description,
                line.account_code,
                line.account_name,
                line.debit_cents.to_i.zero? ? nil : (line.debit_cents.to_d / 100).round(2),
                line.credit_cents.to_i.zero? ? nil : (line.credit_cents.to_d / 100).round(2),
                entry.entry_type,
                entry.created_by&.name
              ]
            end
          end
        end

        filename = ["journal_entries", @start_date, @end_date, @account_code].compact.join("_") + ".csv"
        send_data csv, filename: filename, type: "text/csv; charset=utf-8", disposition: "attachment"
      end

      def journal_entry_params
        params.require(:journal_entry).permit(
          :date, :description,
          lines_attributes: %i[account_encoded debit_pounds credit_pounds notes]
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
          IncomeCategory.find_by(id: id)&.account_code || IncomeCategory::ACCOUNT_CODE_BASE + 1
        when "expense_category"
          ExpenseCategory.find_by(id: id)&.account_code || ExpenseCategory::ACCOUNT_CODE_BASE + 1
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
