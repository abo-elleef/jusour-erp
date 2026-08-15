# frozen_string_literal: true

# Import customers from the cleaned `customers_export.csv` produced by
# script/build_customers_csv.py out of the two legacy exports
# (normal_customers.xlsx + vip_customers.xlsx).
#
# === Local DB (dry-run, then apply) ===
#   FILE=tmp/customers_export.csv COMPANY="SAQR Fried Chicken" \
#     bin/rails customers:import_customer_lists
#
#   FILE=tmp/customers_export.csv COMPANY="SAQR Fried Chicken" APPLY=1 \
#     bin/rails customers:import_customer_lists
#
# === Heroku DB (run locally against Heroku Postgres) ===
#   DATABASE_URL="$(heroku config:get DATABASE_URL -a rest-management-system)" \
#     FILE=tmp/customers_export.csv COMPANY="SAQR Fried Chicken" APPLY=1 \
#     bin/rails customers:import_customer_lists
#
# Optional flags:
#   SKIP_BAD_FORMAT=1 — skip rows whose phone_format_ok column is "no"
#                        (numbers that didn't normalize to a standard
#                        01XXXXXXXXX Egyptian mobile — typos in the source file)
#   REPORT=tmp/customer_import_report.csv — write created/updated/failed rows
namespace :customers do
  desc "Import customers from the cleaned normal+VIP customer list export"
  task import_customer_lists: :environment do
    path = ENV.fetch("FILE") { abort "Set FILE=/path/to/customers_export.csv" }
    abort "FILE not found: #{path}" unless File.file?(path)

    company_key = ENV["COMPANY"].presence || ENV["COMPANY_ID"].presence || ENV["COMPANY_SLUG"].presence
    abort "Set COMPANY='Company Name' (or COMPANY_ID / COMPANY_SLUG)" if company_key.blank?

    company = Company.find_by(id: company_key) if company_key.match?(/\A[0-9a-f-]{36}\z/i)
    company ||= Company.find_by(slug: company_key)
    company ||= Company.find_by(name: company_key)
    company ||= Company.where("LOWER(name) = ?", company_key.downcase).first
    abort "Company not found: #{company_key.inspect}" unless company

    dry_run = ENV["APPLY"].to_s != "1"
    skip_bad_format = ENV["SKIP_BAD_FORMAT"].to_s == "1"

    puts "Company: #{company.name} (#{company.id})"
    puts "File:    #{path}"
    puts "Mode:    #{dry_run ? "DRY-RUN (set APPLY=1 to write)" : "APPLY"}"
    puts "Skip non-standard phone formats: #{skip_bad_format ? "yes" : "no (imported anyway)"}"
    puts "DB:      #{ActiveRecord::Base.connection_db_config.database}"
    puts

    result = Legacy::CustomerListImport.new(
      path: path,
      company: company,
      dry_run: dry_run,
      skip_bad_format: skip_bad_format
    ).call

    puts "Rows processed:              #{result.rows_processed}"
    puts "Rows skipped (bad format):    #{result.rows_skipped_bad_format}"
    puts "Created:  #{result.created.size}#{" (would create)" if dry_run}"
    puts "Updated:  #{result.updated.size}#{" (would update name/phone_secondary)" if dry_run}"
    puts "Existing (no change):         #{result.skipped_existing.size}"
    puts "Addresses added: #{result.addresses_created}#{" (would add)" if dry_run}"
    puts "Failed:   #{result.failed.size}"

    if result.failed.any?
      puts "\nFailed rows (first 30):"
      result.failed.first(30).each do |row, message|
        puts "  ! #{row["name"]} | #{row["phone"]} — #{message}"
      end
      puts "  … #{result.failed.size - 30} more" if result.failed.size > 30
    end

    if (report = ENV["REPORT"].presence)
      FileUtils.mkdir_p(File.dirname(report))
      CSV.open(report, "w") do |csv|
        csv << %w[status name phone phone_secondary error]
        result.created.each { |c, row| csv << ["created", c.name, c.phone, c.phone_secondary, nil] }
        result.updated.each { |c, row| csv << ["updated", c.name, c.phone, c.phone_secondary, nil] }
        result.failed.each { |row, msg| csv << ["failed", row["name"], row["phone"], row["phone_secondary"], msg] }
      end
      puts "\nWrote report: #{report}"
    end

    puts "\nTip: run with APPLY=1 once the dry-run numbers look right."
  end
end
