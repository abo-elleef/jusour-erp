# frozen_string_literal: true

require "csv"

# Import customers inferred from a one-day old-POS orders CSV export.
#
# === Local DB (dry-run, then apply) ===
#   FILE="$HOME/Downloads/طلبات يوم 31 يوليو.xlsx - Page1.csv" \
#   COMPANY="SAQR Fried Chicken" \
#   bin/rails customers:import_legacy_orders
#
#   FILE=... COMPANY="SAQR Fried Chicken" APPLY=1 bin/rails customers:import_legacy_orders
#
# === Heroku DB (recommended: run locally against Heroku Postgres) ===
#   1. Commit + push is NOT required for this path.
#   2. Dry-run:
#        DATABASE_URL="$(heroku config:get DATABASE_URL -a rest-management-system)" \
#        FILE="$HOME/Downloads/طلبات يوم 31 يوليو.xlsx - Page1.csv" \
#        COMPANY="SAQR Fried Chicken" \
#        bin/rails customers:import_legacy_orders
#   3. Apply:
#        DATABASE_URL="$(heroku config:get DATABASE_URL -a rest-management-system)" \
#        FILE=... COMPANY="SAQR Fried Chicken" APPLY=1 \
#        bin/rails customers:import_legacy_orders
#
# === Heroku one-off dyno (after code is deployed) ===
#   heroku run bash -a rest-management-system
#   # inside the dyno, curl/scp the CSV to /tmp/orders.csv, then:
#   FILE=/tmp/orders.csv COMPANY="SAQR Fried Chicken" APPLY=1 \
#     bin/rails customers:import_legacy_orders
#
# Optional flags:
#   NAME_ONLY=1  — also create name-only customers with @import.invalid emails
#   REPORT=tmp/legacy_customers_preview.csv — write extracted candidates CSV
#   COMPANY / COMPANY_ID / COMPANY_SLUG — target tenant
namespace :customers do
  desc "Import customers from an old POS daily orders CSV export"
  task import_legacy_orders: :environment do
    path = ENV.fetch("FILE") { abort "Set FILE=/path/to/export.csv" }
    abort "FILE not found: #{path}" unless File.file?(path)

    company_key = ENV["COMPANY"].presence || ENV["COMPANY_ID"].presence || ENV["COMPANY_SLUG"].presence
    abort "Set COMPANY='Company Name' (or COMPANY_ID / COMPANY_SLUG)" if company_key.blank?

    company = Company.find_by(id: company_key) if company_key.match?(/\A[0-9a-f-]{36}\z/i)
    company ||= Company.find_by(slug: company_key)
    company ||= Company.find_by(name: company_key)
    company ||= Company.where("LOWER(name) = ?", company_key.downcase).first
    abort "Company not found: #{company_key.inspect}" unless company

    dry_run = ENV["APPLY"].to_s != "1"
    include_name_only = ENV["NAME_ONLY"].to_s == "1"

    puts "Company: #{company.name} (#{company.id})"
    puts "File:    #{path}"
    puts "Mode:    #{dry_run ? "DRY-RUN (set APPLY=1 to write)" : "APPLY"}"
    puts "Name-only rows: #{include_name_only ? "included (synthetic email)" : "skipped (need phone)"}"
    puts "DB:      #{ActiveRecord::Base.connection_db_config.database}"
    puts

    result = Legacy::OldPosOrdersCustomerImport.new(
      path: path,
      company: company,
      dry_run: dry_run,
      include_name_only: include_name_only
    ).call

    with_phone = result.candidates.count { |c| c.phone.present? }
    name_only = result.candidates.count { |c| c.phone.blank? }
    importable = result.candidates.count { |c| c.phone.present? || (include_name_only && c.email.present?) }

    puts "Orders skipped (cash / table walk-ins): #{result.skipped_rows}"
    puts "Unique named customers in file:         #{result.candidates.size}"
    puts "  with valid Egyptian mobile:           #{with_phone}"
    puts "  name-only (no phone):                 #{name_only}"
    puts "  importable this run:                  #{importable}"
    puts
    puts "Created:  #{result.created.size}#{' (would create)' if dry_run}"
    puts "Updated:  #{result.updated.size}#{' (would update name)' if dry_run}"
    puts "Existing: #{result.skipped_existing.size}"
    puts "Failed:   #{result.failed.size}"

    format_candidate = lambda do |candidate|
      parts = []
      parts << (candidate.name.presence || "(no name)")
      parts << candidate.phone if candidate.phone
      parts << candidate.email if candidate.email
      parts << "acct=#{candidate.legacy_account_code}" if candidate.legacy_account_code
      parts << "orders=#{candidate.order_count}"
      parts.join(" | ")
    end

    if result.created.any?
      puts "\nCreated / would create:"
      result.created.first(30).each do |_record, candidate|
        puts "  + #{format_candidate.call(candidate)}"
      end
      puts "  … #{result.created.size - 30} more" if result.created.size > 30
    end

    if result.failed.any?
      puts "\nFailed:"
      result.failed.each do |candidate, message|
        puts "  ! #{format_candidate.call(candidate)} — #{message}"
      end
    end

    if (report = ENV["REPORT"].presence)
      FileUtils.mkdir_p(File.dirname(report))
      CSV.open(report, "w") do |csv|
        csv << %w[name phone email legacy_account_code order_count importable]
        result.candidates.each do |c|
          csv << [c.name, c.phone, c.email, c.legacy_account_code, c.order_count, c.phone.present? || c.email.present?]
        end
      end
      puts "\nWrote candidate report: #{report}"
    end

    puts "\nTip: only #{with_phone} of #{result.candidates.size} named customers have a usable phone in this export."
    puts "     Use NAME_ONLY=1 to also create the rest with synthetic emails, or supply a richer customer dump."
  end
end
