# frozen_string_literal: true

module Accounting
  # The age buckets shared by a single customer's statement and the company-wide
  # AR/AP aging reports, so "31–60" means the same thing everywhere.
  module AgingBuckets
    ALL = %i[not_due days_1_30 days_31_60 days_61_90 days_90_plus].freeze

    def self.for(overdue_days)
      return :not_due     if overdue_days <= 0
      return :days_1_30   if overdue_days <= 30
      return :days_31_60  if overdue_days <= 60
      return :days_61_90  if overdue_days <= 90

      :days_90_plus
    end
  end
end
