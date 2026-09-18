# frozen_string_literal: true

# Issues a voucher for every expense and income taken before vouchers existed.
#
#   bin/rails vouchers:backfill          # dry run, prints what it would write
#   bin/rails vouchers:backfill[commit]  # writes
#
# These vouchers document cash that had already moved; they post nothing. The
# records they describe each wrote their own treasury transaction and journal
# entry at the time, and those are correct. Re-posting them through a voucher
# would either double the cash or force us to delete and rewrite historical
# treasury rows — and balance_after_cents is a stored running balance shown as a
# column on the treasury and supplier pages, so rewriting those rows would stamp
# today's balance across years of history for no gain.
#
# Which rows are historical is not a guess: a record that names a treasury and
# has no allocation can only predate the switch, because from the switch onward
# naming a treasury raises a voucher and therefore an allocation.
namespace :vouchers do
  desc "Issue documenting vouchers for expenses and incomes recorded before vouchers existed"
  task :backfill, [:commit] => :environment do |_t, args|
    commit = args[:commit].to_s == "commit"
    warn(commit ? "== WRITING ==" : "== DRY RUN (pass [commit] to write) ==")

    totals = Hash.new(0)

    Company.find_each do |company|
      previous = Current.company
      Current.company = company
      begin
        totals[:payments] += backfill_side(
          Expense.where.not(treasury_id: nil), Voucher::PAYMENT, :expense_date, company, commit
        )
        totals[:receipts] += backfill_side(
          Income.where.not(treasury_id: nil), Voucher::RECEIPT, :income_date, company, commit
        )
      ensure
        Current.company = previous
      end
    end

    warn ""
    warn "payment vouchers (سند صرف): #{totals[:payments]}"
    warn "receipt vouchers (سند قبض): #{totals[:receipts]}"
    warn ""
    warn "These post nothing — the records they describe already moved the cash." if commit
  end

  def backfill_side(scope, direction, date_column, company, commit)
    created = 0

    scope.find_each do |record|
      next if PaymentAllocation.exists?(settles: record)

      created += 1
      next unless commit

      ActiveRecord::Base.transaction do
        voucher = Voucher.create!(
          company: company,
          direction: direction,
          treasury: record.treasury,
          user: record.user,
          amount_cents: record.amount_cents,
          voucher_date: record.public_send(date_column),
          notes: record.description,
          backfilled_at: Time.current
        )
        PaymentAllocation.create!(
          company: company, payment: voucher,
          settles: record, amount_cents: record.amount_cents
        )
      end
    end

    created
  end
end
