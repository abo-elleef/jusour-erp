# frozen_string_literal: true

# Recognise POS takings in the ledger for every active branch.
#
# Locations on manual business days post when the day is closed. Locations on
# automatic days have no close event, so this is what posts them — run it nightly
# (Heroku Scheduler, cron) for the day that just ended:
#
#   bin/rails accounting:post_daily_sales              # yesterday, every company
#   bin/rails "accounting:post_daily_sales[2026-09-01]"
#   bin/rails "accounting:post_daily_sales[2026-09-01,2026-09-06]"   # backfill a range
#
# Safe to re-run: each day's entry is replaced, never duplicated.
namespace :accounting do
  desc "Post POS sales to the ledger for a date (defaults to yesterday)"
  task :post_daily_sales, %i[from to] => :environment do |_t, args|
    from = args[:from].present? ? Date.parse(args[:from]) : Date.yesterday
    to   = args[:to].present? ? Date.parse(args[:to]) : from

    posted = 0
    Company.find_each do |company|
      previous = Current.company
      Current.company = company
      begin
        Location.active.branches.ordered.each do |location|
          (from..to).each do |date|
            Accounting::PostDailySalesJob.perform_now(location.id, date)
            posted += 1
          end
        end
      ensure
        Current.company = previous
      end
    end

    puts "Posted #{posted} location-days (#{from}#{" → #{to}" if to != from})."
  end
end
