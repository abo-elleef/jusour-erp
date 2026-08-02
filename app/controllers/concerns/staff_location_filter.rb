# frozen_string_literal: true

# Location picker shared by attendance and staff index:
# blank = all locations, "company_wide" = all_locations flag, else a branch id.
module StaffLocationFilter
  extend ActiveSupport::Concern

  COMPANY_WIDE_FILTER = "company_wide"

  private

  def load_staff_location_filter
    @filter_locations = filterable_staff_locations
    @location_filter = params[:location_id].to_s
    @company_wide_staff = @location_filter == COMPANY_WIDE_FILTER
    @location = selected_staff_location
  end

  def filterable_staff_locations
    Location.active.ordered.where(id: current_user.accessible_location_ids)
  end

  def selected_staff_location
    return if @location_filter.blank? || @company_wide_staff

    @filter_locations.find_by(id: @location_filter)
  end

  def apply_staff_location_filter(scope)
    if @company_wide_staff
      scope.where(all_locations: true)
    elsif @location
      scope.joins(:user_locations)
        .where(user_locations: { location_id: @location.id })
        .distinct
    else
      scope
    end
  end
end
