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
    if @pos_location.blank? && @pos_locations.size == 1
      session[:pos_location_id] = @pos_locations.first.id
      @pos_location = @pos_locations.first
    end

    load_pos_workstations
  end

  def load_pos_workstations
    @pos_workstations = if @pos_location
                          @pos_location.workstations.active.ordered.includes(:receipt_printer)
                        else
                          Workstation.none
                        end
    @pos_workstation = current_pos_workstation

    if @pos_workstation.blank? && @pos_workstations.size == 1
      session[:pos_workstation_id] = @pos_workstations.first.id
      @pos_workstation = @pos_workstations.first
    elsif @pos_workstation.present? && @pos_location.present? && @pos_workstation.location_id != @pos_location.id
      session.delete(:pos_workstation_id)
      @pos_workstation = nil
    end
  end

  def current_pos_location
    return if session[:pos_location_id].blank?

    @pos_locations&.find { |loc| loc.id == session[:pos_location_id] } ||
      Location.active.branches.find_by(id: session[:pos_location_id])
  end

  def current_pos_workstation
    return if session[:pos_workstation_id].blank?

    @pos_workstations&.find { |ws| ws.id == session[:pos_workstation_id] } ||
      Workstation.active.find_by(id: session[:pos_workstation_id])
  end
end
