# frozen_string_literal: true

module Sales
  # The funnel/drop-off/rep-performance picture management asked for: where open
  # leads are sitting, why the lost ones didn't convert, and who's actually
  # closing. Scoped to leads *created* in the period — a lead opened before the
  # window but converted/lost inside it would otherwise double-count across runs.
  class LeadsReportService
    GRANULARITIES = %w[day week month].freeze

    FunnelRow = Struct.new(:stage, :count, keyword_init: true)
    DropReasonRow = Struct.new(:reason, :count, :percent, keyword_init: true)
    TrendRow = Struct.new(:period, :label, :count, keyword_init: true)
    PerformanceRow = Struct.new(:user_id, :name, :assigned, :converted, :lost, keyword_init: true) do
      def conversion_rate
        decided = converted + lost
        decided.zero? ? 0.0 : (converted * 100.0 / decided).round(1)
      end
    end

    def initialize(start_date, end_date)
      @start_date = start_date
      @end_date = end_date
    end

    def funnel
      counts = leads.group(:stage).count
      (Lead::STAGES - Lead::TERMINAL_STAGES).map { |stage| FunnelRow.new(stage: stage, count: counts[stage].to_i) }
    end

    # All leads created in the period, open or decided — unlike #funnel, which
    # only covers the still-open stages (that's what the funnel chart wants).
    def total_created
      leads.count
    end

    def conversion_rate
      converted = leads.where(stage: "converted").count
      lost = leads.where(stage: "lost").count
      decided = converted + lost
      decided.zero? ? 0.0 : (converted * 100.0 / decided).round(1)
    end

    # Average days from creation to conversion, for leads converted in the period.
    def average_days_to_convert
      rows = leads.where(stage: "converted").where.not(converted_at: nil).pluck(:created_at, :converted_at)
      return 0.0 if rows.empty?

      total_days = rows.sum { |created, converted| (converted.to_date - created.to_date).to_i }
      (total_days.to_f / rows.size).round(1)
    end

    def drop_reasons
      counts = leads.where(stage: "lost").group(:lost_reason).count
      total = counts.values.sum
      return [] if total.zero?

      Lead::LOST_REASONS.filter_map do |reason|
        count = counts[reason].to_i
        next if count.zero?

        DropReasonRow.new(reason: reason, count: count, percent: (count * 100.0 / total).round(1))
      end.sort_by { |r| -r.count }
    end

    # New leads per day/week/month — "how many leads came in every month" reads
    # off this directly, bucket chosen to fit the range unless asked for one.
    # Weeks run Saturday–Friday (config.beginning_of_week), not Postgres'
    # Monday-based date_trunc, so bucketing happens in Ruby via Date#beginning_of_week
    # — same approach as Accounting::CategoryAnalysisService/Inventory::TransferTrendsService.
    def trend(granularity: nil)
      granularity = GRANULARITIES.include?(granularity.to_s) ? granularity.to_s : default_granularity

      daily_counts = leads.group(Arel.sql("DATE(created_at)")).count
      buckets = Hash.new(0)
      daily_counts.each { |date, count| buckets[period_for(date.to_date, granularity)] += count }

      buckets.sort.map { |period, count| TrendRow.new(period: period, label: period_label(period, granularity), count: count) }
    end

    def by_performance
      assigned = leads.group(:assigned_user_id).count
      converted = leads.where(stage: "converted").group(:assigned_user_id).count
      lost = leads.where(stage: "lost").group(:assigned_user_id).count
      names = User.where(id: assigned.keys).pluck(:id, :name).to_h

      assigned.map do |user_id, count|
        PerformanceRow.new(
          user_id: user_id, name: names[user_id].to_s,
          assigned: count, converted: converted[user_id].to_i, lost: lost[user_id].to_i
        )
      end.sort_by { |r| -r.conversion_rate }
    end

    private

    def leads
      @leads ||= Lead.where(created_at: @start_date.beginning_of_day..@end_date.end_of_day)
    end

    def period_for(date, granularity)
      case granularity
      when "week" then date.beginning_of_week
      when "month" then date.beginning_of_month
      else date
      end
    end

    def period_label(period, granularity)
      case granularity
      when "month" then I18n.l(period, format: "%B %Y")
      when "week" then week_label(period)
      else I18n.l(period, format: "%a %d %b")
      end
    end

    # Weeks run Saturday to Friday app-wide (config.beginning_of_week) — spell
    # out both ends so the reader isn't left guessing where a week stops.
    def week_label(period)
      finish = period.end_of_week
      start_format = period.month == finish.month ? "%d" : "%d %b"
      "#{I18n.l(period, format: start_format)} – #{I18n.l(finish, format: "%d %b")}"
    end

    def default_granularity
      days = (@end_date - @start_date).to_i
      return "day" if days <= 45
      return "week" if days <= 400

      "month"
    end
  end
end
