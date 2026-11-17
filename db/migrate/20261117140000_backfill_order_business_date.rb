# frozen_string_literal: true

# Reports, the day close and daily COGS now pick orders by business_date (the
# branch's operating day when the order was placed) instead of a clock range.
# Orders from before business_date existed (before 2026-09-16) have none, so
# they get the day the clock formula gave them all along: placed time (else
# opened) in Cairo, less the branch's start hour (else the company's, else 6).
#
# Raw SQL on purpose: migrations must not depend on app models.
class BackfillOrderBusinessDate < ActiveRecord::Migration[7.1]
  def up
    execute <<~SQL.squish
      UPDATE orders SET business_date = date(
        (COALESCE(orders.placed_at, orders.created_at) AT TIME ZONE 'UTC' AT TIME ZONE 'Africa/Cairo')
        - make_interval(hours => COALESCE(
            (SELECT locations.business_day_start_hour FROM locations WHERE locations.id = orders.location_id),
            (SELECT company_settings.business_day_start_hour FROM company_settings
              WHERE company_settings.company_id = orders.company_id LIMIT 1),
            6))
      )
      WHERE business_date IS NULL
    SQL
  end

  def down
    # Data backfill; the days it set are the ones these orders were always reported on.
  end
end
