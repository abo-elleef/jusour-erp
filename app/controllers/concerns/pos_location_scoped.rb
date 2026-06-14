# frozen_string_literal: true

module PosLocationScoped
  extend ActiveSupport::Concern

  included do
    before_action :load_pos_locations
  end

  private

  def load_pos_locations
    @pos_locations = Location.active.branches.ordered
    @pos_location = current_pos_location
    return if @pos_location.present? || @pos_locations.size != 1

    session[:pos_location_id] = @pos_locations.first.id
    @pos_location = @pos_locations.first
  end

  def current_pos_location
    return if session[:pos_location_id].blank?

    @pos_locations&.find { |loc| loc.id == session[:pos_location_id] } ||
      Location.active.branches.find_by(id: session[:pos_location_id])
  end
end
