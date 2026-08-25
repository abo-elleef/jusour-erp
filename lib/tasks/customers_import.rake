# frozen_string_literal: true

require "csv"

# Import customers exported from the previous system.
#
#   bin/rails "customers:import[/path/to/customers_raw.csv,<COMPANY_ID>]"          # dry run (default)
#   bin/rails "customers:import[/path/to/customers_raw.csv,<COMPANY_ID>,commit]"   # write for real
#
# CSV header: legacy_code,name,phone1,phone2,address,notes
namespace :customers do
  desc "Import legacy customers from a CSV (dry run unless the 3rd arg is 'commit')"
  task :import, %i[csv_path company_id mode] => :environment do |_t, args|
    csv_path = args[:csv_path]
    company  = Company.find_by(id: args[:company_id])
    dry_run  = args[:mode].to_s != "commit"

    abort "CSV not found: #{csv_path}" unless csv_path && File.exist?(csv_path)
    unless company
      warn "Company not found. Available companies:"
      Company.find_each { |c| warn "  #{c.id}  #{c.name}" }
      abort
    end

    rows = CSV.read(csv_path, headers: true).map(&:to_h)
    puts "Read #{rows.size} rows from #{File.basename(csv_path)}"
    puts "Target company: #{company.name} (#{company.id})"
    puts dry_run ? "MODE: DRY RUN (nothing will be written)\n\n" : "MODE: COMMIT (writing to the database)\n\n"

    result = Customers::LegacyImporter.new(rows: rows, company: company, dry_run: dry_run).call

    puts "── Result ─────────────────────────────"
    puts "  Would create / created:  #{result.created}"
    puts "  Would update / updated:  #{result.updated}"
    puts "  Addresses attached:      #{result.addresses_created}"
    puts "  Notes set:               #{result.notes_set}"
    puts "  Skipped (no phone/email): #{result.skipped_no_contact}"
    puts "  Duplicate phones dropped: #{result.phone_conflicts}"
    puts "  Legacy codes de-duped:   #{result.legacy_deduped}"
    puts "  Validation errors:       #{result.errors.size}"

    if result.errors.any?
      puts "\n── First 20 errors ────────────────────"
      result.errors.first(20).each do |e|
        puts "  row #{e[:row]} (#{e[:name]}): #{e[:messages].join('; ')}"
      end
    end

    if result.skipped_rows.any?
      skipped_path = csv_path.sub(/\.csv\z/i, "") + "_skipped.csv"
      CSV.open(skipped_path, "w") do |out|
        out << %w[legacy_code name phone1 phone2 address notes]
        result.skipped_rows.each { |r| out << r.values_at("legacy_code", "name", "phone1", "phone2", "address", "notes") }
      end
      puts "\nWrote #{result.skipped_rows.size} skipped (no-contact) rows to: #{skipped_path}"
    end

    puts "\nDry run complete — re-run with ,commit as the 3rd argument to write." if dry_run
  end
end
