# frozen_string_literal: true

module Accounting
  # Recognises one location's takings for one business day in the ledger.
  #
  # Locations on manual business days post as part of closing the day; locations on
  # automatic days have no close event, so this job (driven nightly by
  # `accounting:post_daily_sales`) is what posts them. Re-running is safe — the
  # day's entry is replaced, not duplicated.
  class PostDailySalesJob < ApplicationJob
    queue_as :default

    def perform(location_id, business_date)
      location = Location.unscoped.find(location_id)
      with_company(location.company) do
        JournalEntryService.record_daily_sales!(
          location: location,
          business_date: business_date.to_date,
          user: posting_user(location)
        )
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
