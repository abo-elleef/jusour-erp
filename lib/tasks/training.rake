# frozen_string_literal: true

# Build a training company from an existing company's catalogue, so new staff can
# practise on the real menu and ingredients without seeing anything real.
# Only ever reads from the source. Safe to run on production with a fresh SLUG.
#
#   SOURCE_SLUG=saqr-local SLUG=training-01 bin/rails training:create
#   SOURCE_SLUG=saqr-local SLUG=training-01 NAME='Training — Batch 1' \
#     PASSWORD='Train2026!' MATES=ahmed,sara,omar MATE_ROLE=manager \
#     bin/rails training:create
#
# OPENING_STOCK=0 leaves every ingredient at zero on-hand.
namespace :training do
  desc "Create a training company from another company's catalogue (SOURCE_SLUG + SLUG required)"
  task create: :environment do
    result = begin
      Training::CompanyCopy.call(
        source_slug: ENV["SOURCE_SLUG"],
        slug: ENV["SLUG"],
        name: ENV["NAME"],
        password: ENV["PASSWORD"],
        mates: ENV["MATES"].to_s.split(","),
        mate_role: ENV["MATE_ROLE"].presence || "manager",
        opening_stock: ENV["OPENING_STOCK"] != "0"
      )
    rescue ArgumentError => e
      abort "ERROR: #{e.message}"
    end

    company = result.company
    puts "Training company ready: #{company.name} (slug=#{company.slug}, id=#{company.id})"
    puts
    puts "Owner login: #{result.owner_email} / #{result.password}"
    result.mates.each { |email| puts "Mate login:  #{email} / #{result.password}" }
    puts
    puts "Copied:"
    result.counts.sort_by { |k, _| k.to_s }.each do |key, count|
      puts format("  %-28s %d", key, count)
    end

    if result.skipped.any?
      puts
      puts "Skipped #{result.skipped.size} row(s) the SOURCE company can no longer save itself:"
      result.skipped.group_by { |row| [row[:model], row[:reason]] }.each do |(model, reason), rows|
        puts format("  %-28s %d  (%s)", model, rows.size, reason)
        rows.first(5).each { |row| puts "      - #{row[:label]}" }
        puts "      … and #{rows.size - 5} more" if rows.size > 5
      end
      puts "  These are pre-existing data problems in #{ENV['SOURCE_SLUG']}, worth fixing there."
    end

    puts
    puts "Add more people in the super-admin panel, or re-run with MATES=name1,name2."
  end
end
