# frozen_string_literal: true

# Rewrites payroll history onto the staff-account model.
#
# Before: an advance was its own record (PayrollAdvance) posting to 5500, a
# finalized month paid the remainder straight out of a treasury posting to 5501,
# and a staff meal posted to 5502. After: every employee has their own account
# (User#account_code, 2500+). Finalizing a month credits it with what was
# earned (Dr 5501); every payment to them — what used to be an advance, and the
# month's payout — is a voucher that debits it; a staff meal debits it.
#
#   bin/rails payroll:convert_to_staff_accounts           # dry run: does it all, prints, rolls back
#   APPLY=1 bin/rails payroll:convert_to_staff_accounts   # writes
#
# Treasury rows are never re-created. The existing row is re-pointed at the new
# voucher (source and kind only), so no treasury balance moves and the stored
# running balance (balance_after_cents) shown on the treasury pages keeps its
# history. Only journal entries are rewritten.
#
# Every month becomes vouchers, but only months the ledger actually covers
# post to it. Before the cutover — by default the first month with any revenue
# in the ledger (July 2026 here: May and June have no revenue and no expenses
# in it at all) — the vouchers are issued as backfilled documents that post
# nothing, the way vouchers:backfill documented pre-voucher cash, and any
# payroll entry already sitting in those months is removed. Posting them would
# give May and June a payroll loss against revenue the ledger never had. Each
# of those months nets to zero per employee (earned = paid), so leaving both
# sides out keeps every staff balance right. Override with FROM=YYYY-MM.
#
# Idempotent: converted advances carry converted_voucher_id, converted months
# carry payout_voucher_id (or have nothing to pay out), and every journal entry
# is rewritten through destroy_for_source!.
namespace :payroll do
  desc "Move payroll history (advances, payouts, staff meals) onto each employee's own account"
  task convert_to_staff_accounts: :environment do
    apply = ENV["APPLY"].to_s == "1"
    warn(apply ? "== WRITING ==" : "== DRY RUN (APPLY=1 to write) — everything below is rolled back ==")

    ActiveRecord::Base.transaction do
      Company.find_each do |company|
        Current.company = company
        StaffAccountConversion.new(company).run!
      ensure
        Current.company = nil
      end

      raise ActiveRecord::Rollback unless apply
    end

    warn(apply ? "\nWritten." : "\nRolled back; nothing was written.")
  end
end

# A plain object in the rake file, like MoneyPathChecker: it exists for this
# one rewrite and nothing in the app should be able to call it.
class StaffAccountConversion
  def initialize(company)
    @company = company
    @notes = []
    @cutover = cutover_month
  end

  def run!
    return if PayrollAdvance.none? && PayrollSnapshot.none? && staff_meal_lines.none? && unallocated_staff_vouchers.none?

    puts "\n#{'=' * 72}\n#{@company.name}\n#{'=' * 72}"
    puts "Ledger cutover: #{@cutover ? @cutover.strftime('%Y-%m') : 'none — every month posts'} " \
         "(earlier months become backfilled vouchers that post nothing)"
    wages_before = wages_by_month
    treasuries_before = treasury_balances
    drift_before = drift

    counts = {
      orphans: purge_orphan_advance_entries!,
      voucher_advances: convert_voucher_advances!,
      old_advances: convert_old_advances!,
      months: convert_snapshots!,
      meals: convert_staff_meals!,
      staff_vouchers: repost_unallocated_staff_vouchers!
    }

    report_counts(counts)
    report_wages(wages_before, wages_by_month)
    report_treasuries(treasuries_before, treasury_balances, drift_before, drift)
    report_balances
    report_leftovers
    @notes.each { |n| puts "  NOTE #{n}" }
  end

  private

  # ── 1. Advances already paid by a voucher: drop the allocation, name the
  #       employee as the voucher's party, re-post. ───────────────────────
  def convert_voucher_advances!
    allocations = PaymentAllocation.where(settles_type: "PayrollAdvance", payment_type: "Voucher").includes(:payment)
    allocations.count.tap do
      allocations.each do |allocation|
        voucher = allocation.payment
        advance = PayrollAdvance.find(allocation.settles_id)
        allocation.delete

        voucher.update_columns(party_type: "User", party_id: advance.user_id,
                               counterparty: voucher.counterparty.presence || advance.user.name)
        if posts?(voucher.voucher_date)
          repost_voucher!(voucher.reload)
        else
          voucher.update_columns(backfilled_at: Time.current)
          retag!(voucher)
          Accounting::JournalEntryService.destroy_for_source!(voucher)
        end
        Accounting::JournalEntryService.destroy_for_source!(advance)
        advance.update_columns(converted_voucher_id: voucher.id)
      end
    end
  end

  # ── 2. Advances from before vouchers: issue the voucher they never had and
  #       hand it the advance's own treasury row. ───────────────────────────
  def convert_old_advances!
    converted = 0
    PayrollAdvance.unconverted.includes(:user, :paid_by, :treasury).order(:paid_on, :created_at).each do |advance|
      txn = TreasuryTransaction.find_by(source_record: advance)
      if txn.nil?
        @notes << "advance #{advance.id} (#{advance.user.name}, #{advance.paid_on}, #{money(advance.amount_cents)}) has no treasury row — left alone"
        next
      end

      voucher = issue_voucher!(treasury: advance.treasury, user: advance.paid_by, employee: advance.user,
                               amount_cents: txn.amount_cents.abs, date: advance.paid_on,
                               notes: advance.notes.presence || txn.description)
      take_over!(txn, voucher)
      Accounting::JournalEntryService.destroy_for_source!(advance)
      Accounting::JournalEntryService.record_voucher!(voucher) if posts?(voucher.voucher_date)
      advance.update_columns(converted_voucher_id: voucher.id)
      converted += 1
    end
    converted
  end

  # ── 3. Finalized months: post the earnings to the employee's account, and
  #       turn the payout into a voucher. ─────────────────────────────────
  def convert_snapshots!
    converted = 0
    PayrollSnapshot.where(payout_voucher_id: nil).includes(:user, :finalized_by, :treasury).order(:payroll_month).each do |snapshot|
      posting = posts?(snapshot.payroll_month)
      if posting
        Accounting::JournalEntryService.record_payroll_accrual!(snapshot)
      else
        Accounting::JournalEntryService.destroy_for_source!(snapshot)
      end

      txn = TreasuryTransaction.find_by(source_record: snapshot)
      if txn
        if txn.amount_cents.abs != snapshot.remaining_pay_cents
          @notes << "#{snapshot.user.name} #{snapshot.payroll_month.strftime('%Y-%m')}: payout row #{money(txn.amount_cents.abs)} " \
                    "≠ remaining_pay #{money(snapshot.remaining_pay_cents)} — used the treasury row"
        end
        voucher = issue_voucher!(treasury: txn.treasury, user: snapshot.finalized_by, employee: snapshot.user,
                                 amount_cents: txn.amount_cents.abs, date: snapshot.paid_on || txn.occurred_on,
                                 notes: txn.description)
        take_over!(txn, voucher)
        Accounting::JournalEntryService.record_voucher!(voucher) if posting
        snapshot.update_columns(payout_voucher_id: voucher.id)
      elsif snapshot.remaining_pay_cents.positive?
        @notes << "#{snapshot.user.name} #{snapshot.payroll_month.strftime('%Y-%m')}: marked paid #{money(snapshot.remaining_pay_cents)} " \
                  "but has no treasury row — earnings posted, no payout voucher"
      end
      converted += 1
    end
    converted
  end

  # ── 4. Staff meals: same entry, the employee's account instead of 5502. ──
  def convert_staff_meals!
    converted = 0
    staff_meal_lines.includes(:journal_entry).find_each do |line|
      order = Order.find_by(id: line.journal_entry.source_record_id)
      employee = order&.staff_meal_user
      if employee.nil?
        @notes << "staff meal entry #{line.journal_entry.entry_number} has no employee on its order — left on 5502"
        next
      end

      line.update_columns(account_code: employee.account_code, account_name: employee.account_name,
                          account_type: employee.account_type)
      converted += 1
    end

    missing = Payment.joins(:order).where(payment_method: "staff_deduction", status: "completed",
                                          orders: { company_id: @company.id })
                     .where.not(order_id: JournalEntry.where(source_record_type: "Order").select(:source_record_id))
                     .count
    @notes << "#{missing} staff meal(s) never had a journal entry — not created" if missing.positive?
    converted
  end

  # ── 5. Vouchers already naming an employee, paying nothing in particular —
  #       these posted to accrued expenses (2300) and now hit the employee. ──
  def repost_unallocated_staff_vouchers!
    vouchers = unallocated_staff_vouchers.includes(:party).order(:voucher_date).to_a
    return 0 if vouchers.empty?

    puts "\nVouchers already naming an employee (now counted on their account — check each was meant as pay):"
    vouchers.each do |v|
      puts format("  %-14s %-10s %-8s %-24s %12s  %s", v.number, v.voucher_date, v.direction,
                  v.party&.name.to_s[0, 24], money(v.amount_cents), v.notes.to_s[0, 40])
      repost_voucher!(v)
    end
    vouchers.size
  end

  # ── Helpers ───────────────────────────────────────────────────────────

  # ── 0. Entries left behind by advances that were deleted — their cash
  #       row went with them, the entry didn't. ────────────────────────────
  def purge_orphan_advance_entries!
    orphans = JournalEntry.where(source_record_type: "PayrollAdvance")
                          .where.not(source_record_id: PayrollAdvance.select(:id)).includes(:lines).to_a
    orphans.each do |je|
      @notes << "removed orphan #{je.entry_number} (#{je.date}, #{je.description}, #{money(je.lines.sum(&:debit_cents))}) — its advance was deleted"
      je.destroy!
    end
    orphans.size
  end

  def cutover_month
    if ENV["FROM"].present?
      Date.parse("#{ENV['FROM']}-01")
    else
      first = JournalEntryLine.joins(:journal_entry)
                              .where(journal_entries: { company_id: @company.id }, account_type: "revenue")
                              .minimum("journal_entries.date")
      first&.beginning_of_month
    end
  end

  def posts?(date) = @cutover.nil? || date >= @cutover

  # Before the cutover the voucher only documents a treasury row that already
  # exists; it posts nothing, exactly like vouchers:backfill.
  def issue_voucher!(treasury:, user:, employee:, amount_cents:, date:, notes:)
    Voucher.create!(
      company: @company, direction: Voucher::PAYMENT, purpose: Voucher::SETTLEMENT,
      treasury: treasury, user: user, amount_cents: amount_cents, voucher_date: date,
      number: Voucher.next_number(direction: Voucher::PAYMENT, company: @company, year: date.year),
      party_type: "User", party_id: employee.id, counterparty: employee.name, notes: notes,
      backfilled_at: posts?(date) ? nil : Time.current
    )
  end

  def retag!(voucher)
    TreasuryTransaction.where(source_record: voucher, treasury_id: voucher.treasury_id)
                       .update_all(kind: voucher.treasury_kind)
  end

  # The voucher takes over the treasury row as it stands — same amount, same
  # date, same running balance — so the treasury never notices.
  def take_over!(txn, voucher)
    txn.update_columns(source_record_type: "Voucher", source_record_id: voucher.id, kind: voucher.treasury_kind)
  end

  def repost_voucher!(voucher)
    retag!(voucher)
    Accounting::JournalEntryService.record_voucher!(voucher)
  end

  def unallocated_staff_vouchers
    Voucher.active.posting.where(party_type: "User")
           .where.not(id: PaymentAllocation.where(payment_type: "Voucher").select(:payment_id))
           .where.not(id: PayrollAdvance.where.not(converted_voucher_id: nil).select(:converted_voucher_id))
           .where.not(id: PayrollSnapshot.where.not(payout_voucher_id: nil).select(:payout_voucher_id))
  end

  def staff_meal_lines
    JournalEntryLine.joins(:journal_entry)
                    .where(journal_entries: { company_id: @company.id, source_record_type: "Order" },
                           account_code: Accounting::JournalEntryService::STAFF_MEAL_CODE)
  end

  def wages_by_month
    JournalEntryLine.joins(:journal_entry)
                    .where(journal_entries: { company_id: @company.id }, account_code: Accounting::ChartOfAccountsService::POOLED_WAGES_CODES)
                    .group(Arel.sql("to_char(journal_entries.date, 'YYYY-MM')"))
                    .sum(Arel.sql("debit_cents - credit_cents"))
  end

  def treasury_balances
    Treasury.unscoped.where(company_id: @company.id).pluck(:id, :name, :balance_cents).to_h { |id, n, b| [id, [n, b]] }
  end

  # Same invariant as accounting:verify_money_paths: what the treasury says
  # moved, less what the ledger says moved.
  def drift
    Treasury.unscoped.where(company_id: @company.id).to_h do |t|
      txn = TreasuryTransaction.where(treasury_id: t.id).sum(:amount_cents)
      lines = JournalEntryLine.joins(:journal_entry)
                              .where(journal_entries: { company_id: @company.id }, treasury_id: t.id)
      ledger = t.treasury_type == "supplier_ap" ? lines.sum("credit_cents - debit_cents") : lines.sum("debit_cents - credit_cents")
      [t.id, txn - ledger]
    end
  end

  def report_counts(c)
    puts "\nConverted:"
    puts "  orphan advance entries removed: #{c[:orphans]}"
    puts "  advances already on a voucher : #{c[:voucher_advances]}"
    puts "  advances given a voucher      : #{c[:old_advances]}"
    puts "  finalized months re-posted    : #{c[:months]}"
    puts "  staff meal entries moved      : #{c[:meals]}"
    puts "  staff vouchers re-posted      : #{c[:staff_vouchers]}"
  end

  def report_wages(before, after)
    puts "\nWages expense by month (5500 + 5501 + 5502) — what the P&L will show:"
    puts format("  %-8s %14s %14s %14s", "MONTH", "BEFORE", "AFTER", "CHANGE")
    (before.keys | after.keys).sort.each do |m|
      b = before[m].to_i
      a = after[m].to_i
      flag = b == a ? "" : "  <-"
      puts format("  %-8s %14s %14s %14s%s", m, money(b), money(a), money(a - b), flag)
    end
  end

  def report_treasuries(balances_before, balances_after, drift_before, drift_after)
    moved = balances_after.select { |id, (_, bal)| balances_before.dig(id, 1) != bal }
    if moved.empty?
      puts "\nTreasury balances: unchanged."
    else
      puts "\nTreasury balances CHANGED (should not happen):"
      moved.each { |id, (name, bal)| puts "  #{name}: #{money(balances_before.dig(id, 1))} -> #{money(bal)}" }
    end

    changed = drift_after.reject { |id, v| drift_before[id] == v }
    return puts("Ledger vs treasury drift: unchanged.") if changed.empty?

    puts "Ledger vs treasury drift (treasury total less ledger total). It moves because payroll cash the ledger"
    puts "never saw now reaches it — that is a fix, but it also uncovers other pre-ledger cash still missing:"
    changed.each do |id, v|
      puts format("  %-30s %14s -> %14s", balances_after.dig(id, 0).to_s[0, 30], money(drift_before[id]), money(v))
    end
  end

  def report_balances
    rows = User.unscoped.where(company_id: @company.id).order(:name).filter_map do |u|
      bal = u.staff_balance_cents
      [u, bal] unless bal.zero?
    end
    return puts("\nStaff balances: all zero.") if rows.empty?

    puts "\nStaff balances after conversion (+ owed to them, − they owe the company):"
    rows.each do |u, bal|
      open_months = PayrollSnapshot.where(user: u).maximum(:payroll_month)
      puts format("  %-28s %14s   last finalized: %s", u.name.to_s[0, 28], money(bal), open_months&.strftime("%Y-%m") || "never")
    end
    puts "  A negative balance is expected for anyone paid during a month not yet finalized."
  end

  def report_leftovers
    leftover = JournalEntryLine.joins(:journal_entry)
                               .where(journal_entries: { company_id: @company.id },
                                      account_code: [Accounting::JournalEntryService::ADVANCE_CODE,
                                                     Accounting::JournalEntryService::STAFF_MEAL_CODE])
                               .group(:account_code).count
    puts "\nStill on 5500 / 5502 (hand-written entries, left as they are): #{leftover.inspect}" if leftover.any?
  end

  def money(cents) = format("%.2f", cents.to_i / 100.0)
end
