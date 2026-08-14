# frozen_string_literal: true

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
