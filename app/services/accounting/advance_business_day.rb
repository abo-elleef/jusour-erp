# frozen_string_literal: true

module Accounting
  class AdvanceBusinessDay
    Result = Struct.new(:success?, :location, :from_date, :to_date, :error, :skipped?, keyword_init: true)
    BatchResult = Struct.new(:advanced, :failed, :skipped, keyword_init: true)

    class Error < StandardError; end

    def self.call(location:, user:)
      new(location: location, user: user).call
    end

    def self.call_all(user:)
      advanced = []
      failed = []
      skipped = []

      Location.active.branches.ordered.find_each do |location|
        unless BusinessDay.manual?(location: location)
          skipped << Result.new(
            success?: false,
            location: location,
            from_date: nil,
            to_date: nil,
            error: I18n.t("accounting.business_days.errors.not_manual"),
            skipped?: true
          )
          next
        end

        result = call(location: location, user: user)
        if result.success?
          advanced << result
        else
          failed << result
        end
      end

      BatchResult.new(advanced: advanced, failed: failed, skipped: skipped)
    end

    def initialize(location:, user:)
      @location = location
      @user = user
    end

    def call
      unless BusinessDay.manual?(location: @location)
        return failure(I18n.t("accounting.business_days.errors.not_manual"))
      end

      unless @location.branch?
        return failure(I18n.t("accounting.business_days.errors.not_a_branch"))
      end

      current = BusinessDay.ensure_current_day!(@location, user: @user)
      open_drawers = CashDrawerSession.open.where(location_id: @location.id).includes(:user)

      if open_drawers.any?
        names = open_drawers.map { |s| s.user.name }.uniq.join(", ")
        return failure(I18n.t("accounting.business_days.errors.open_drawers", names: names))
      end

      from_date = current.business_date
      to_date = from_date + 1.day

      ActiveRecord::Base.transaction do
        # Closing the day is when its takings become revenue.
        JournalEntryService.record_daily_sales!(
          location: @location, business_date: from_date, user: @user
        )
        current.update!(closed_at: Time.current, closed_by: @user)
        LocationOperatingDay.create!(
          company: @location.company,
          location: @location,
          business_date: to_date,
          opened_at: Time.current,
          opened_by: @user
        )
      end

      AuditLogEntry.record!(
        action: "business_day.advanced",
        record: @location,
        user: @user,
        changes_snapshot: { from: from_date.iso8601, to: to_date.iso8601 }
      )

      Result.new(success?: true, location: @location, from_date: from_date, to_date: to_date, error: nil, skipped?: false)
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors.full_messages.to_sentence)
    end

    private

    def failure(message)
      Result.new(success?: false, location: @location, from_date: nil, to_date: nil, error: message, skipped?: false)
    end
  end
end
