# frozen_string_literal: true

namespace :orders do
  # Nightly safety net for empty carts the register never got to clean up: a
  # session that expired, a tablet that was closed, a shift nobody counted.
  # The register already deletes an empty cart when the cashier moves on and at
  # drawer close; this catches what is left. Only orders older than MIN_AGE_HOURS
  # (default 24) go, so a cart a cashier is still building is never touched.
  #
  #   bin/rails orders:discard_empty_drafts
  #   MIN_AGE_HOURS=48 DRY_RUN=1 bin/rails orders:discard_empty_drafts
  desc "Delete draft orders that were saved but never got an item"
  task discard_empty_drafts: :environment do
    min_age = ENV.fetch("MIN_AGE_HOURS", "24").to_f.hours
    dry_run = ENV["DRY_RUN"].present?
    total = 0

    Company.find_each do |company|
      previous = Current.company
      Current.company = company
      begin
        stale = Order.empty_drafts.where(created_at: ...min_age.ago)
        count = 0
        stale.find_each do |order|
          next count += 1 if dry_run

          count += 1 if Orders::DiscardEmptyDraftService.call(order)
        end
        total += count
        puts "#{company.name}: #{count} empty draft(s) #{dry_run ? 'would be' : ''} deleted".squeeze(" ") if count.positive?
      ensure
        Current.company = previous
      end
    end

    puts "Done — #{total} empty draft order(s) #{dry_run ? 'found (dry run)' : 'deleted'}."
  end
end
