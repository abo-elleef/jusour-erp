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

# Re-costs the daily COGS rows, e.g. after the costing changed (modifier recipes
# were added to it on 2026-11-13). Rebuilds every branch-day that has completed
# orders in the range; each row is replaced, or removed when the day costs
# nothing, so it is safe to re-run. COGS rows carry no treasury and post no
# journal entry, so this changes the management figure only.
#
#   bin/rails accounting:rebuild_daily_cogs                           # every day up to yesterday
#   bin/rails "accounting:rebuild_daily_cogs[2026-10-01,2026-11-12]"
namespace :accounting do
  desc "Re-cost the daily COGS rows for every branch-day with sales in a range"
  task :rebuild_daily_cogs, %i[from to] => :environment do |_t, args|
    to = args[:to].present? ? Date.parse(args[:to]) : Date.yesterday

    rebuilt = 0
    before_total = 0
    after_total = 0
    Company.find_each do |company|
      previous = Current.company
      Current.company = company
      begin
        category = ExpenseCategory.find_by(name: Accounting::DailyCogsService::CATEGORY_NAME)
        next if category.nil?

        user = User.where(company_id: company.id, role: "owner").first ||
               User.where(company_id: company.id).first
        next if user.nil?

        orders = Order.completed.where.not(location_id: nil)
        if args[:from].present?
          orders = orders.where(created_at: BusinessDay.range_between(Date.parse(args[:from]), to))
        end
        locations = Location.where(id: orders.distinct.pluck(:location_id)).index_by(&:id)
        days = orders.pluck(:location_id, :created_at)
                     .map { |location_id, at| [location_id, BusinessDay.for(at, location: locations[location_id])] }
                     .uniq
                     .select { |_, date| date <= to }

        cogs = Expense.where(expense_category_id: category.id, is_auto_generated: true, source_record_type: "Location")
        before_total += cogs.sum(:amount_cents).to_i

        days.each do |location_id, date|
          Accounting::DailyCogsService.call(location: locations[location_id], business_date: date, user: user)
          rebuilt += 1
        end

        after_total += cogs.sum(:amount_cents).to_i
        puts "#{company.name}: #{days.size} branch-days"
      ensure
        Current.company = previous
      end
    end

    puts "Rebuilt #{rebuilt} branch-day COGS rows. COGS total #{before_total} → #{after_total} cents (#{after_total - before_total >= 0 ? '+' : ''}#{after_total - before_total})."
  end
end
