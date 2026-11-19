# frozen_string_literal: true

module Leads
  # The morning follow-up alert: one notification to a lead's assigned user for
  # each open lead whose next follow-up is today or already past
  # (Lead.due_for_follow_up). Run daily by `leads:notify_follow_ups`.
  #
  # Idempotent per lead per Cairo day — a re-run (or a second scheduler hit)
  # skips any lead that already got today's notification. Companies without the
  # leads feature, or with the cadence turned off, get nothing.
  class FollowUpNotifier
    MESSAGE_KEY = "lead_follow_up_due"

    def self.call(company, today: Date.current)
      new(company, today).call
    end

    def initialize(company, today)
      @company = company
      @today = today
    end

    # Returns the number of notifications created.
    def call
      previous = Current.company
      Current.company = @company
      return 0 unless @company.feature_enabled?(:leads) && Setting.lead_follow_up_cadence?

      already = already_notified_lead_ids
      count = 0
      ::Lead.due_for_follow_up.includes(:assigned_user).find_each do |lead|
        user = lead.assigned_user
        next if user.nil? || !user.active? || already.include?(lead.id)

        notify(lead, user)
        count += 1
      end
      count
    ensure
      Current.company = previous
    end

    private

    def notify(lead, user)
      ::Notification.create!(
        recipient: user, company: @company, notification_type: "sales",
        params: { message_key: MESSAGE_KEY,
                  message_params: { lead_id: lead.id, lead_name: lead.name,
                                    follow_up_on: lead.next_follow_up_at.iso8601,
                                    overdue: lead.next_follow_up_at < @today }.deep_stringify_keys,
                  lead_id: lead.id }
      )
    end

    def already_notified_lead_ids
      day = @today.in_time_zone.all_day
      ::Notification.where(created_at: day)
        .where("params->>'message_key' = ?", MESSAGE_KEY)
        .pluck(Arel.sql("params->>'lead_id'")).to_set
    end
  end
end
