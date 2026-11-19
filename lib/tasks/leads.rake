# frozen_string_literal: true

namespace :leads do
  # Morning follow-up alert (Leads::FollowUpNotifier): each lead due today or
  # overdue notifies its assigned user once per day. Safe to re-run.
  # Heroku Scheduler: daily at 05:30 UTC (07:30 Cairo).
  #
  #   bin/rails leads:notify_follow_ups
  desc "Notify assigned users of leads due (or overdue) for follow-up today"
  task notify_follow_ups: :environment do
    total = 0
    Company.find_each do |company|
      count = Leads::FollowUpNotifier.call(company)
      total += count
      puts "#{company.name}: #{count} follow-up notification(s)" if count.positive?
    end
    puts "Done — #{total} follow-up notification(s) sent."
  end
end
