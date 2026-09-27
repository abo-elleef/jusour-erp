# frozen_string_literal: true

require "csv"

# Sales history (invoices + returns) exported from the previous system.
#
# Two steps, so the data can be eyeballed between them and the same CSV can be
# replayed on any environment:
#
#   1. convert (local only — needs the .xlsx)
#        bin/rails "sales_history:convert[/path/to/export.xlsx,tmp/sales_history.csv]"
#
#   2. import (local or Heroku; reads a path, or "-" for STDIN)
#        bin/rails "sales_history:import[tmp/sales_history.csv,<COMPANY_ID_OR_SLUG>]"          # dry run
#        bin/rails "sales_history:import[tmp/sales_history.csv,<COMPANY_ID_OR_SLUG>,commit]"   # write
#
# Optional 4th/5th args: location (name or id) and the phone to give customers the
# export has no contact details for.
#
# A second export format — a per-customer "كشف حساب: عميل" (account statement)
# workbook, one file per customer, mixing invoices/returns with real payment
# vouchers and a running balance — uses its own convert step, but feeds the
# SAME import task above (see Legacy::CustomerStatementWorkbook):
#
#   1. convert_statements (local only — a directory of .xlsx files)
#        bin/rails "sales_history:convert_statements[/path/to/dir,tmp/sales_history.csv,tmp/customer_balances.csv]"
#
#   2. import (as above) — then post each customer's legacy closing balance as
#      their AR opening balance:
#        bin/rails "sales_history:import_opening_balances[tmp/customer_balances.csv,<COMPANY_ID_OR_SLUG>]"          # dry run
#        bin/rails "sales_history:import_opening_balances[tmp/customer_balances.csv,<COMPANY_ID_OR_SLUG>,commit]"   # write
def find_company(ref)
  return nil if ref.blank?

  Company.find_by(id: ref) || Company.find_by(slug: ref)
end

def company_not_found!
  warn "Company not found. Available:"
  Company.find_each { |c| warn "  #{c.id}  #{c.slug}  #{c.name}" }
  abort
end

namespace :sales_history do
  desc "Convert a legacy sales-details .xlsx into the flat import CSV"
  task :convert, %i[xlsx_path csv_path] => :environment do |_t, args|
    require Rails.root.join("lib/legacy/sales_history_workbook")

    xlsx = args[:xlsx_path]
    out  = args[:csv_path].presence || "tmp/sales_history.csv"
    abort "Workbook not found: #{xlsx}" unless xlsx && File.exist?(xlsx)

    workbook = Legacy::SalesHistoryWorkbook.new(xlsx)
    documents = workbook.documents
    rows = workbook.to_rows

    FileUtils.mkdir_p(File.dirname(out))
    CSV.open(out, "w") do |csv|
      csv << Legacy::SalesHistoryWorkbook::HEADERS
      rows.each { |row| csv << row }
    end

    invoices = documents.count { |d| d.type == "invoice" }
    returns  = documents.size - invoices
    puts "Documents: #{documents.size} (#{invoices} invoices, #{returns} returns)"
    puts "Line items: #{rows.size}"
    puts "Customers:  #{documents.map { |d| [d.customer_code, d.customer_name] }.uniq.size}"
    puts "Dates:      #{documents.map(&:date).min} → #{documents.map(&:date).max}"
    puts "Wrote #{out}"
  end

  desc "Convert a directory of legacy per-customer account-statement .xlsx files (see " \
       "Legacy::CustomerStatementWorkbook) into the flat import CSV, plus a closing-balance CSV"
  task :convert_statements, %i[dir_path csv_path balances_csv_path] => :environment do |_t, args|
    require Rails.root.join("lib/legacy/customer_statement_workbook")

    dir = args[:dir_path]
    out = args[:csv_path].presence || "tmp/sales_history.csv"
    balances_out = args[:balances_csv_path].presence || "tmp/customer_balances.csv"
    abort "Directory not found: #{dir}" unless dir && Dir.exist?(dir)

    files = Dir.glob(File.join(dir, "*.xlsx")).sort
    abort "No .xlsx files found in #{dir}" if files.empty?

    all_rows = []
    balance_rows = []
    total_docs = 0
    errors = []

    files.each do |path|
      workbook = Legacy::CustomerStatementWorkbook.new(path)
      rows = workbook.to_rows
      all_rows.concat(rows)
      total_docs += workbook.documents.size

      computed = workbook.computed_balance_cents
      reported = workbook.reported_current_balance_cents
      mismatch = reported && (computed - reported).abs > 100

      balance_rows << [workbook.customer_code, workbook.customer_name, computed, reported,
                        workbook.last_transaction_date, File.basename(path)]
      if mismatch
        errors << "#{File.basename(path)}: computed #{computed / 100.0}, " \
                  "sheet's own \"current balance\" said #{reported / 100.0}"
      end
    rescue StandardError => e
      errors << "#{File.basename(path)}: #{e.class} #{e.message}"
    end

    FileUtils.mkdir_p(File.dirname(out))
    CSV.open(out, "w") do |csv|
      csv << Legacy::CustomerStatementWorkbook::HEADERS
      all_rows.each { |row| csv << row }
    end

    FileUtils.mkdir_p(File.dirname(balances_out))
    CSV.open(balances_out, "w") do |csv|
      csv << %w[customer_code customer_name balance_cents reported_balance_cents last_transaction_date source_file]
      balance_rows.each { |row| csv << row }
    end

    puts "Files:       #{files.size}"
    puts "Customers:   #{balance_rows.size}"
    puts "Documents:   #{total_docs} (invoices + returns)"
    puts "Line items:  #{all_rows.size}"
    puts "Wrote #{out}"
    puts "Wrote #{balances_out}"

    if errors.any?
      puts "\n── Balance mismatches / errors (review before trusting) ──"
      errors.each { |e| puts "  #{e}" }
    end
  end

  desc "Import legacy sales history as drafts (dry run unless the 3rd arg is 'commit')"
  task :import, %i[csv_path company_id mode location phone] => :environment do |_t, args|
    company = find_company(args[:company_id])
    dry_run = args[:mode].to_s != "commit"

    company_not_found! unless company

    source = args[:csv_path].to_s
    data =
      if source == "-" || source.empty?
        puts "Reading CSV from STDIN…"
        $stdin.read
      else
        abort "CSV not found: #{source}" unless File.exist?(source)
        File.read(source)
      end

    rows = CSV.parse(data, headers: true).map(&:to_h)
    puts "Read #{rows.size} line rows · target: #{company.name} (#{company.id})"
    puts dry_run ? "MODE: DRY RUN (nothing written)\n\n" : "MODE: COMMIT\n\n"

    result = Sales::LegacyHistoryImporter.new(
      rows: rows, company: company, dry_run: dry_run,
      location: args[:location], fallback_phone: args[:phone]
    ).call

    puts "── Result ─────────────────────────────"
    puts "  Location used:            #{result.location_name}"
    puts "  Customers created:        #{result.customers_created}"
    puts "  Customers backdated:      #{result.customers_backdated}"
    puts "  Customers w/o contact:    #{result.customers_without_contact}"
    puts "  Products created:         #{result.products_created}"
    puts "  Invoices created (draft): #{result.invoices_created}"
    puts "  Credit notes (draft):     #{result.credit_notes_created}"
    puts "  Line items:               #{result.lines_created}"
    puts "  Free-of-charge lines:     #{result.free_lines}"
    puts "  Docs w/ legacy discount:  #{result.discount_docs}"
    puts "  Already imported (skip):  #{result.skipped_existing}"
    puts "  Errors:                   #{result.errors.size}"

    if result.notes.any?
      puts "\n── Notices ────────────────────────────"
      result.notes.first(30).each { |n| puts "  #{n}" }
      puts "  … #{result.notes.size - 30} more" if result.notes.size > 30
    end

    if result.errors.any?
      puts "\n── First 20 errors ────────────────────"
      result.errors.first(20).each { |e| puts "  #{e[:doc]}: #{e[:messages].join('; ')}" }
    end

    puts "\nDry run complete — re-run with ,commit as the 3rd arg to write." if dry_run
  end

  desc "Post each customer's legacy closing balance as their AR opening balance " \
       "(dry run unless the 3rd arg is 'commit')"
  task :import_opening_balances, %i[csv_path company_id mode] => :environment do |_t, args|
    company = find_company(args[:company_id])
    dry_run = args[:mode].to_s != "commit"

    company_not_found! unless company

    source = args[:csv_path].to_s
    abort "CSV not found: #{source}" unless File.exist?(source)

    rows = CSV.parse(File.read(source), headers: true).map(&:to_h)
    puts "Read #{rows.size} customer balances · target: #{company.name} (#{company.id})"
    puts dry_run ? "MODE: DRY RUN (nothing written)\n\n" : "MODE: COMMIT\n\n"

    result = Sales::LegacyOpeningBalanceImporter.new(rows: rows, company: company, dry_run: dry_run).call

    puts "── Result ─────────────────────────────"
    puts "  Balances posted:                 #{result.posted}"
    puts "  Already had a balance (skipped): #{result.skipped_existing}"
    puts "  Zero balance (skipped):          #{result.skipped_zero}"
    puts "  Credit balance (skipped):        #{result.skipped_credit.size}"
    puts "  Customer not found:              #{result.customer_not_found.size}"
    puts "  Mismatches vs sheet's own figure: #{result.mismatches.size}"

    if result.customer_not_found.any?
      puts "\n── Customers not found (import their invoices/returns first) ──"
      result.customer_not_found.first(30).each { |c| puts "  #{c}" }
    end

    if result.skipped_credit.any?
      puts "\n── Credit balances (owe THEM — needs a manual decision) ──"
      result.skipped_credit.each { |c| puts "  #{c}" }
    end

    if result.mismatches.any?
      puts "\n── Balance mismatches (review before trusting) ──"
      result.mismatches.first(30).each { |m| puts "  #{m}" }
    end

    puts "\nDry run complete — re-run with ,commit as the 3rd arg to write." if dry_run
  end
end
