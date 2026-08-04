# frozen_string_literal: true

# Shared admin date-range filter (start_date / end_date) persisted in the session
# so navigating between accounting and inventory report pages keeps the range.
#
# Priority: URL params → session → page default.
module SessionDateRange
  extend ActiveSupport::Concern

  SESSION_START_KEY = :admin_start_date
  SESSION_END_KEY = :admin_end_date

  private

  def parse_date_range(default_start: 7.days.ago.to_date)
    default_end = Date.current

    if date_range_param_submitted?
      @start_date = safe_date_param(:start_date) || session_stored_start || default_start.to_date
      @end_date = safe_date_param(:end_date) || session_stored_end || default_end
      persist_date_range_to_session!
    elsif session_date_range_present?
      @start_date = session_stored_start
      @end_date = session_stored_end
    else
      @start_date = default_start.to_date
      @end_date = default_end
    end
  end

  def persist_date_range_to_session!
    session[SESSION_START_KEY] = @start_date.iso8601
    session[SESSION_END_KEY] = @end_date.iso8601
  end

  def date_range_param_submitted?
    params[:start_date].present? || params[:end_date].present?
  end

  def session_date_range_present?
    session_stored_start.present? && session_stored_end.present?
  end

  def session_stored_start
    safe_date(session[SESSION_START_KEY])
  end

  def session_stored_end
    safe_date(session[SESSION_END_KEY])
  end

  def safe_date_param(key)
    safe_date(params[key])
  end

  def safe_date(value)
    return if value.blank?

    value.to_date
  rescue ArgumentError, TypeError, Date::Error
    nil
  end
end
