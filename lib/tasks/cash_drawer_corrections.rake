# frozen_string_literal: true

# One-off correction of a miscounted drawer that has already been reconciled and
# banked into its safe, after the business day has moved on (ReopenCashDrawer only
# works on the same day).
#
# Lowers the counted cash by AMOUNT pounds and re-posts what the count drives.
#   - A drawer closed before over/short documents (variance_documented false)
#     booked the count: its drawer_reconcile and drawer_deposit lines and their
#     journal entries are re-posted, and the safe ends AMOUNT lower.
#   - A documented drawer booked the expected cash, which doesn't change: its
#     over/short Income or shortage voucher is rebuilt for the new difference.
#     The Income's receipt voucher is raised on commit, so a dry run does not
#     show its effect on the safe's balance.
# The drawer treasury nets to the same as before. Expected cash, the payments
# and the orders are untouched.
#
# Two things are deliberately preserved:
#   - the session's updated_at: a counted drawer's order window ends at it
#     (CashDrawerSession#order_window), so touching it would pull later orders in;
#   - the original journal entry dates: the sync re-posts with Date.current.
#
# Dry run by default (everything runs, then rolls back). Pass "commit" to write:
#   bin/rails "accounting:correct_drawer_count[<session uuid>,400,<reason>]"
#   bin/rails "accounting:correct_drawer_count[<session uuid>,400,<reason>,commit]"
namespace :accounting do
  desc "Lower the counted cash of a reconciled drawer and re-post its treasury/journal entries"
  task :correct_drawer_count, %i[session_id amount reason commit] => :environment do |_t, args|
    commit = args[:commit].to_s == "commit"
    reduce_cents = (BigDecimal(args[:amount].to_s) * 100).to_i
    reason = args[:reason].to_s.strip
    abort "amount must be positive" unless reduce_cents.positive?
    abort "reason is required" if reason.blank?

    session = CashDrawerSession.unscoped.find(args[:session_id])
    previous_company = Current.company
    Current.company = session.company
    session = CashDrawerSession.find(session.id)

    warn(commit ? "== WRITING ==" : "== DRY RUN (pass commit as the 4th arg to write) ==")
    abort "drawer is #{session.status}, expected reconciled" unless session.status == "reconciled"

    new_counted = session.counted_cash_cents - reduce_cents
    abort "counted would go below zero" if new_counted.negative?

    fmt = ->(cents) { format("%.2f", cents.to_i / 100.0) }
    entries = lambda do
      JournalEntry.where(source_record_type: "CashDrawerSession", source_record_id: session.id)
                  .order(:id).map { |e| "    ##{e.entry_number} #{e.date} #{e.description} (#{fmt.call(e.lines.sum(:debit_cents))})" }
    end
    treasuries = [session.treasury, session.deposit_treasury].compact
    balances = -> { treasuries.map { |t| "    #{t.name}: #{fmt.call(t.reload.balance_cents)}" } }

    ActiveRecord::Base.transaction do
      before = {
        counted: session.counted_cash_cents, variance: session.variance_cents,
        updated_at: session.updated_at
      }
      warn "Drawer #{session.id} — #{session.user.name}, #{session.session_date}"
      warn "  counted  #{fmt.call(before[:counted])} → #{fmt.call(new_counted)}"
      warn "  variance #{fmt.call(before[:variance])} → #{fmt.call(before[:variance] - reduce_cents)}"
      warn "  balances before:", *balances.call
      warn "  journal before:", *entries.call

      dates = %w[reconcile deposit].index_with do |kind|
        JournalEntry.where(source_record_type: "CashDrawerSession", source_record_id: session.id)
                    .where("description LIKE ?", "%[#{kind}]%").pick(:date)
      end

      # update_columns: keeps updated_at, so the order window stays where it was.
      session.update_columns(
        counted_cash_cents: new_counted,
        variance_cents: before[:variance] - reduce_cents
      )

      ::Accounting::TreasuryLedgerService.sync_drawer_reconcile!(session)
      ::Accounting::TreasuryLedgerService.sync_drawer_deposit!(session)
      ::Accounting::DrawerVarianceDocuments.sync!(session, by: nil)

      dates.each do |kind, date|
        next unless date

        JournalEntry.where(source_record_type: "CashDrawerSession", source_record_id: session.id)
                    .where("description LIKE ?", "%[#{kind}]%")
                    .update_all(date: date)
      end

      raise "updated_at moved" unless session.reload.updated_at == before[:updated_at]

      AuditLogEntry.record!(
        action: "cash_drawer.count_corrected",
        record: session,
        changes_snapshot: {
          counted_before: before[:counted], counted_after: new_counted,
          variance_before: before[:variance], variance_after: session.variance_cents,
          reduced_by_cents: reduce_cents, reason: reason
        }
      )

      warn "  balances after:", *balances.call
      warn "  journal after:", *entries.call

      raise ActiveRecord::Rollback unless commit
    end
    warn(commit ? "== WRITTEN ==" : "== ROLLED BACK (dry run) ==")
  ensure
    Current.company = previous_company if defined?(previous_company)
  end
end
