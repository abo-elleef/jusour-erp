# frozen_string_literal: true

module Accounting
  # Recognises one location's takings for one business day in the ledger, and the
  # cost of sales that goes with them.
  #
  # Locations on manual business days post as part of closing the day; locations on
  # automatic days have no close event, so this job (driven nightly by
  # `accounting:post_daily_sales`) is what posts them. Re-running is safe — the
  # day's entry and its cost row are both replaced, not duplicated.
  class PostDailySalesJob < ApplicationJob
    queue_as :default

    def perform(location_id, business_date)
      location = Location.unscoped.find(location_id)
      date = business_date.to_date
      with_company(location.company) do
        user = posting_user(location)
        JournalEntryService.record_daily_sales!(
          location: location,
          business_date: date,
          user: user
        )
        DailyCogsService.call(location: location, business_date: date, user: user)
      end
    end

    private

    # Entries need an author; the day's takings belong to no one person, so they are
    # filed under the company owner.
    def posting_user(location)
      User.unscoped.where(company_id: location.company_id, role: "owner").first ||
        User.unscoped.where(company_id: location.company_id).first
    end
  end
end
