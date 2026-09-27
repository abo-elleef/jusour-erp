# frozen_string_literal: true

module Sales
  # Posts each customer's legacy closing balance — computed from their imported
  # account-statement (see Legacy::CustomerStatementWorkbook) — as a single AR
  # opening-balance ledger entry, rather than replaying every historical receipt
  # and payment voucher one by one.
  #
  # A customer must already exist (created by importing their invoices/returns
  # via Sales::LegacyHistoryImporter, matched here by legacy_code or name) and
  # must not already carry an AR balance; re-running is safe.
  class LegacyOpeningBalanceImporter
    MISMATCH_THRESHOLD_CENTS = 100

    Result = Struct.new(:posted, :skipped_existing, :skipped_zero, :skipped_credit,
                        :customer_not_found, :mismatches, :dry_run, keyword_init: true)

    def initialize(rows:, company:, dry_run: true, user: nil)
      @rows = rows
      @company = company
      @dry_run = dry_run
      @user = user
      @result = Result.new(posted: 0, skipped_existing: 0, skipped_zero: 0, skipped_credit: [],
                            customer_not_found: [], mismatches: [], dry_run: dry_run)
    end

    def call
      previous = Current.company
      Current.company = @company

      ActiveRecord::Base.transaction do
        @recorder = resolve_user!
        @rows.each { |row| import_row(row) }

        raise ActiveRecord::Rollback if @dry_run
      end

      @result
    ensure
      Current.company = previous
    end

    private

    def import_row(row)
      code = row["customer_code"].to_s.strip
      name = row["customer_name"].to_s.strip
      balance_cents = row["balance_cents"].to_i

      customer = find_customer(code, name)
      unless customer
        @result.customer_not_found << "#{code} #{name}".strip
        return
      end

      note_mismatch(customer, code, row)
      return if skip?(customer, code, balance_cents)

      Accounting::CustomerArLedgerService.new(customer).open_balance!(
        amount_cents: balance_cents, user: @recorder, occurred_on: occurred_on(row),
        description: "Legacy opening balance (Sky Soft import)"
      )
      @result.posted += 1
    end

    # A positive balance (customer owes us) is a normal opening receivable.
    # A negative one (receipts on file exceed recorded invoices — a real credit
    # balance, or a data artifact — see #note_mismatch) isn't something
    # CustomerArLedgerService#open_balance! can post: it only raises a
    # receivable, never lowers one. Surface these for a manual decision instead
    # of guessing.
    def skip?(customer, code, balance_cents)
      if balance_cents.zero?
        @result.skipped_zero += 1
        return true
      end

      if balance_cents.negative?
        @result.skipped_credit << "#{customer.display_name} (legacy #{code}): #{balance_cents / 100.0}"
        return true
      end

      if customer.ar_balance_cents.nonzero?
        @result.skipped_existing += 1
        return true
      end

      false
    end

    def note_mismatch(customer, code, row)
      reported_cents = row["reported_balance_cents"].presence&.to_i
      return unless reported_cents

      balance_cents = row["balance_cents"].to_i
      return unless (balance_cents - reported_cents).abs > MISMATCH_THRESHOLD_CENTS

      @result.mismatches << "#{customer.display_name} (legacy #{code}): posting #{balance_cents / 100.0}, " \
                            "the sheet's own \"current balance\" said #{reported_cents / 100.0}"
    end

    def occurred_on(row)
      date = row["last_transaction_date"].presence
      date ? Date.parse(date) : Date.current
    rescue Date::Error
      Date.current
    end

    def find_customer(code, name)
      scope = Customer.where(company: @company)
      (code.present? && scope.find_by(legacy_code: code)) ||
        (name.present? && scope.where("lower(name) = ?", name.downcase).first)
    end

    def resolve_user!
      user = @user || User.unscoped.where(company: @company).find_by(role: "owner") ||
             User.unscoped.where(company: @company).first
      raise ArgumentError, "#{@company.name} has no user to attribute the import to" if user.blank?

      user
    end
  end
end
