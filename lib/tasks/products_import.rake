# frozen_string_literal: true

require "csv"

# Import products (as ingredients) from a CSV exported from the previous system.
#
#   bin/rails "products:import[/path/to/products_raw.csv,<COMPANY_ID>]"          # dry run
#   bin/rails "products:import[/path/to/products_raw.csv,<COMPANY_ID>,commit]"   # write
#
# CSV header: code,name,unit_raw,cost,selling_price
namespace :products do
  desc "Import products as ingredients from a CSV (dry run unless the 3rd arg is 'commit')"
  task :import, %i[csv_path company_id mode] => :environment do |_t, args|
    csv_path = args[:csv_path]
    company  = Company.find_by(id: args[:company_id])
    dry_run  = args[:mode].to_s != "commit"

    abort "CSV not found: #{csv_path}" unless csv_path && File.exist?(csv_path)
    unless company
      warn "Company not found. Available:"
      Company.find_each { |c| warn "  #{c.id}  #{c.name}" }
      abort
    end

    rows = CSV.read(csv_path, headers: true).map(&:to_h)
    puts "Read #{rows.size} rows · target: #{company.name} (#{company.id})"
    puts dry_run ? "MODE: DRY RUN (nothing written)\n\n" : "MODE: COMMIT\n\n"

    result = Inventory::ProductImporter.new(rows: rows, company: company, dry_run: dry_run).call

    puts "── Result ─────────────────────────────"
    puts "  Created:            #{result.created}"
    puts "  Updated:            #{result.updated}"
    puts "  Skipped (no name):  #{result.skipped_no_name}"
    puts "  Validation errors:  #{result.errors.size}"
    if result.errors.any?
      puts "\n── First 20 errors ────────────────────"
      result.errors.first(20).each { |e| puts "  row #{e[:row]} (#{e[:name]}): #{e[:messages].join('; ')}" }
    end
    puts "\nDry run complete — re-run with ,commit as the 3rd arg to write." if dry_run
  end
end
