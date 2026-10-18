# frozen_string_literal: true

# ── Repair window ────────────────────────────────────────────────────────────
# The ledger repairs in this file run from 2026-08-01 open-ended forward, not for
# a single month: whatever they fix can recur in any later period, and a task that
# only ever looked at August would quietly leave September onward broken.
#
# The default start is deliberate. June and July 2026 predate the journal-entry
# feature, so their advances were never posted at all; rewriting those months is a
# decision to take on purpose, not a side effect of running a repair. Pass FROM to
# reach them.
#
#   FROM=2026-06     # widen back to June
#   TO=2026-09       # close the window at the end of September
#
def repair_window_start
  ENV["FROM"].presence ? parse_window_date(ENV["FROM"]) : Date.new(2026, 8, 1)
end

def repair_window_end
  ENV["TO"].presence ? parse_window_date(ENV["TO"], last_day: true) : nil
end

# Accepts YYYY-MM or YYYY-MM-DD. A bare month means the whole month: the first day
# as a start, the last day as an end.
def parse_window_date(raw, last_day: false)
  value = raw.to_s.strip
  if value =~ /\A\d{4}-\d{2}\z/
    d = Date.parse("#{value}-01")
    last_day ? d.end_of_month : d
  else
    Date.parse(value)
  end
rescue ArgumentError
  abort "Bad date #{raw.inspect} — use YYYY-MM or YYYY-MM-DD."
end

def repair_window_label
  finish = repair_window_end
  finish ? "#{repair_window_start} .. #{finish}" : "#{repair_window_start} onward"
end

def in_repair_window(scope, column)
  finish = repair_window_end
  finish ? scope.where(column => repair_window_start..finish)
         : scope.where(column => repair_window_start..)
end


# Stamp old attendance-grid overtime bonuses with the auto note so they show
# on Accounting → Attendance. Newer grid overtime already has this note;
# staff-page overtime with a custom note is left alone.
#
# Dry-run (prints matches, writes nothing):
#   bin/rails payroll_adjustments:tag_attendance_overtime
#
# Apply:
#   APPLY=1 bin/rails payroll_adjustments:tag_attendance_overtime
#
# Optional tenant filter:
#   COMPANY="SAQR Fried Chicken" APPLY=1 bin/rails payroll_adjustments:tag_attendance_overtime
namespace :payroll_adjustments do
  desc "Set the attendance overtime note on bonus/overtime records that have blank notes"
  task tag_attendance_overtime: :environment do
    dry_run = ENV["APPLY"].to_s != "1"
    company_key = ENV["COMPANY"].presence || ENV["COMPANY_ID"].presence || ENV["COMPANY_SLUG"].presence
    company = nil
    if company_key.present?
      company = Company.find_by(id: company_key) if company_key.match?(/\A[0-9a-f-]{36}\z/i)
      company ||= Company.find_by(slug: company_key)
      company ||= Company.find_by(name: company_key)
      company ||= Company.where("LOWER(name) = ?", company_key.downcase).first
      abort "Company not found: #{company_key.inspect}" unless company
    end

    scope = PayrollAdjustment.unscoped
      .where(kind: "bonus", unit_type: "overtime")
      .where("COALESCE(TRIM(notes), '') = ''")
    scope = scope.where(company_id: company.id) if company

    tagged_notes = PayrollAdjustment.attendance_overtime_notes
    puts "Company: #{company ? "#{company.name} (#{company.id})" : "all tenants"}"
    puts "Mode:    #{dry_run ? "DRY-RUN (set APPLY=1 to write)" : "APPLY"}"
    puts "Note:    #{tagged_notes.join(" / ")}"
    puts "Matches: #{scope.count}"
    puts

    updated = 0
    scope.includes(:user, :company).find_each do |adj|
      locale = (adj.company&.locale.presence || I18n.default_locale).to_sym
      note = I18n.t("accounting.attendance.overtime_note", locale: locale)
      user_name = adj.user&.name || "user ##{adj.user_id}"
      puts "  ##{adj.id}  #{adj.happened_at}  #{user_name}  #{adj.overtime_hours}h  → #{note.inspect}"

      next if dry_run

      adj.update_columns(notes: note, updated_at: Time.current)
      updated += 1
    end

    if dry_run
      puts
      puts "No rows written. Re-run with APPLY=1 to stamp notes."
    else
      puts
      puts "Updated #{updated} overtime bonus(es)."
    end
  end
end

# Deletes journal entries left behind by deleted payroll advances.
#
# A record's journal entry used to survive the record: deleting an expense, an
# income or a payroll advance removed its treasury movement and left the entry
# standing, so the P&L went on reporting money against something nobody could open
# and the cash flow — which reads the treasury — stopped agreeing with it. Every
# delete path now takes the entry with it; this clears what they already left.
#
# Dry-run (prints matches, writes nothing):
#   bin/rails accounting:purge_orphan_entries
#
# Runs over FROM (default 2026-08-01) onward; add TO to close the window.
#
# Apply:
#   APPLY=1 bin/rails accounting:purge_orphan_entries
namespace :accounting do
  # source_record_type => the model that should still hold the record
  ORPHANABLE_SOURCES = {
    "Expense" => "Expense",
    "Income" => "Income",
    "PayrollAdvance" => "PayrollAdvance"
  }.freeze

  desc "Delete journal entries whose expense, income or payroll advance no longer exists"
  task purge_orphan_entries: :environment do
    apply = ENV["APPLY"].to_s == "1"
    puts "Window: #{repair_window_label}"

    orphans = ORPHANABLE_SOURCES.flat_map do |source_type, model_name|
      model = model_name.constantize
      in_repair_window(
        JournalEntry.unscoped
          .where(source_record_type: source_type)
          .where.not(source_record_id: model.unscoped.select(:id)),
        :date
      ).to_a
    end.sort_by(&:date)

    # A source whose cash is still sitting on a treasury is not an orphan at all —
    # the record it belongs to is still live somewhere this query cannot see, and
    # deleting its entry would take a real charge off the P&L.
    with_cash = orphans.select { |e| TreasuryTransaction.unscoped.exists?(source_record_id: e.source_record_id) }
    doomed    = orphans - with_cash

    if doomed.empty?
      puts "No orphaned entries in #{repair_window_label}."
      next
    end

    # What each entry is putting on the P&L — revenue as well as expense, since an
    # orphaned income entry overstates sales exactly as an expense one overstates cost.
    pnl = lambda do |entry|
      JournalEntryLine.where(journal_entry_id: entry.id)
        .where(account_code: 4000...6000)
        .sum("debit_cents - credit_cents")
    end

    puts format("%-12s %-16s %-15s %13s  %s", "DATE", "ENTRY", "SOURCE", "P&L", "DESCRIPTION")
    doomed.each do |entry|
      puts format("%-12s %-16s %-15s %13.2f  %s", entry.date, entry.entry_number,
                  entry.source_record_type, pnl.call(entry) / 100.0, entry.description.to_s[0, 34])
    end
    puts "-" * 78

    doomed.group_by(&:source_record_type).sort.each do |source_type, list|
      puts format("  %-15s %13.2f  (%d entr%s)", source_type,
                  list.sum { |e| pnl.call(e) } / 100.0, list.size, list.size == 1 ? "y" : "ies")
    end
    puts format("  %-15s %13.2f  (%d total)", "ALL", doomed.sum { |e| pnl.call(e) } / 100.0, doomed.size)
    puts "skipped (cash still held): #{with_cash.size}" if with_cash.any?

    unless apply
      puts
      puts "Dry run — nothing deleted. Re-run with APPLY=1 to delete."
      next
    end

    ActiveRecord::Base.transaction { doomed.each(&:destroy!) }
    puts
    puts "Deleted #{doomed.size} orphaned entry(ies)."
  end
end

# Unwinds the reversals that existed before reversal was removed as a concept.
#
# A reversal left the original record on the books and cancelled it with a mirror
# entry, so both the P&L and the cash flow had to be read as a pair to see that
# nothing had happened. Deleting is the only undo now, and this converts the old
# pairs to that shape: the mirror entry goes, and so does the record it cancelled.
#
# Safe by construction: each reversal sits in the same period as its original and
# cancels it exactly, so removing the pair leaves every total where it was. What
# changes is that two lines stop reporting a wash.
#
# Report (writes nothing):
#   bin/rails accounting:unwind_reversals
#
# Runs over FROM (default 2026-08-01) onward; add TO to close the window.
#
# Apply:
#   APPLY=1 bin/rails accounting:unwind_reversals
namespace :accounting do
  desc "Delete legacy reversal entries and the records they cancelled"
  task unwind_reversals: :environment do
    apply = ENV["APPLY"].to_s == "1"

    reversals = in_repair_window(
      JournalEntry.unscoped.where.not(reversal_of_id: nil), :date
    ).order(:date).to_a
    puts "Window: #{repair_window_label}"

    if reversals.empty?
      puts "No reversal entries left to unwind in #{repair_window_label}."
      next
    end

    pairs = reversals.filter_map do |rev|
      original = JournalEntry.unscoped.find_by(id: rev.reversal_of_id)
      record   = original&.source_record_type&.safe_constantize
                         &.unscoped&.find_by(id: original.source_record_id)
      cash = TreasuryTransaction.unscoped.where(source_record_type: "JournalEntry",
                                                source_record_id: rev.id).sum(:amount_cents)
      { reversal: rev, original: original, record: record, cash: cash }
    end

    puts format("%-12s %-16s %-16s %14s  %s", "DATE", "REVERSAL", "ORIGINAL", "CASH", "RECORD")
    pairs.each do |p|
      label = p[:record] ? "#{p[:original].source_record_type} #{p[:record].description.to_s[0, 28]}" : "(record already gone)"
      puts format("%-12s %-16s %-16s %14.2f  %s", p[:reversal].date, p[:reversal].entry_number,
                  p[:original]&.entry_number || "?", p[:cash] / 100.0, label)
    end
    puts "-" * 78
    puts format("%d reversal pair(s); %.2f of journal-entry cash removed from the cash flow",
                pairs.size, pairs.sum { |p| p[:cash] } / 100.0)

    unless apply
      puts "\nReport only — nothing deleted. Re-run with APPLY=1."
      next
    end

    removed_records = 0
    ActiveRecord::Base.transaction do
      pairs.each do |p|
        # The reversal's own cash first: the treasury has to give back what the
        # mirror entry credited it, or deleting the entry would leave the balance
        # carrying a movement whose source is gone.
        TreasuryTransaction.unscoped.where(source_record_type: "JournalEntry",
                                           source_record_id: p[:reversal].id).find_each do |txn|
          txn.treasury.apply_balance_delta!(-txn.amount_cents)
          txn.destroy!
        end
        p[:reversal].destroy!

        # Destroying the record takes its own entry and treasury movement with it.
        next if p[:record].nil?

        Current.company = p[:record].company
        p[:record].destroy!
        removed_records += 1
      end
    end
    puts "\nDeleted #{pairs.size} reversal entry(ies) and #{removed_records} cancelled record(s)."
  ensure
    Current.company = nil
  end
end
