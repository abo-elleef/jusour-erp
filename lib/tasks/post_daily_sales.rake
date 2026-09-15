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

# Replaces the legacy per-order COGS rows with the branch-day rows that took over
# from them. Safe to re-run: the per-order rows are gone after the first pass, and
# each branch-day row is rewritten rather than added to.
#
#   bin/rails accounting:migrate_order_cogs
namespace :accounting do
  desc "Replace legacy per-order COGS expense rows with one row per branch-day"
  task migrate_order_cogs: :environment do
    removed = 0
    rebuilt = 0

    Company.find_each do |company|
      previous = Current.company
      Current.company = company
      begin
        legacy = Expense.where(source_record_type: "Order", is_auto_generated: true)
        next if legacy.empty?

        # Group the orders those rows came from into the branch-days that now own
        # the cost, before the rows that point at them are deleted.
        pairs = Order.where(id: legacy.select(:source_record_id))
                     .where.not(location_id: nil)
                     .includes(:location)
                     .map { |order| [order.location, BusinessDay.for(order.created_at, location: order.location)] }
                     .uniq { |location, date| [location.id, date] }

        removed += legacy.destroy_all.size

        user = User.where(company_id: company.id, role: "owner").first ||
               User.where(company_id: company.id).first
        next if user.nil?

        pairs.each do |location, date|
          Accounting::DailyCogsService.call(location: location, business_date: date, user: user)
          rebuilt += 1
        end
      ensure
        Current.company = previous
      end
    end

    puts "Removed #{removed} per-order COGS rows; rebuilt #{rebuilt} branch-day rows."
  end
end
