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
#        bin/rails "sales_history:import[tmp/sales_history.csv,<COMPANY_ID>]"          # dry run
#        bin/rails "sales_history:import[tmp/sales_history.csv,<COMPANY_ID>,commit]"   # write
#
# Optional 4th/5th args: location (name or id) and the phone to give customers the
# export has no contact details for.
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

  desc "Import legacy sales history as drafts (dry run unless the 3rd arg is 'commit')"
  task :import, %i[csv_path company_id mode location phone] => :environment do |_t, args|
    company = Company.find_by(id: args[:company_id])
    dry_run = args[:mode].to_s != "commit"

    unless company
      warn "Company not found. Available:"
      Company.find_each { |c| warn "  #{c.id}  #{c.name}" }
      abort
    end

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
end
