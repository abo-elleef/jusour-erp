# frozen_string_literal: true

module PosLocationScoped
  extend ActiveSupport::Concern

  # Which branch this device last worked in. Kept in its own cookie rather than the
  # session so it survives the browser being closed — a register sits in one branch,
  # and asking again every morning is what sent cashiers cycling the dropdown to get
  # a branch actually set. Deliberately out of the session cookie, which is already
  # close to its size limit.
  POS_LOCATION_COOKIE = :pos_location_id

  included do
    before_action :load_pos_locations
  end

  private

  def load_pos_locations
    @pos_locations = accessible_pos_locations
    @pos_location = current_pos_location || default_pos_location
    remember_pos_location!(@pos_location)

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

  # An `all_locations` user works company-wide; everyone else sees only the branches
  # they were assigned on their staff record.
  def accessible_pos_locations
    scope = Location.active.branches.ordered
    return scope if current_user.nil? || current_user.all_locations?

    scope.where(id: current_user.location_ids)
  end

  def current_pos_location
    pos_location_for(session[:pos_location_id])
  end

  # Only ever resolves to a branch this user may work in, so a stale id — from a
  # revoked assignment or a branch that was deactivated — falls back to the picker
  # instead of quietly staying selected.
  def pos_location_for(id)
    return if id.blank?

    @pos_locations.find { |loc| loc.id == id }
  end

  def default_pos_location
    pos_location_for(cookies.signed[POS_LOCATION_COOKIE]) || sole_pos_location
  end

  # Auto-select only when there is nothing to choose between — a cashier assigned to
  # one branch never picks it. Anyone with a real choice gets a blank option rather
  # than a pre-selected guess: the dropdown showing the first branch while nothing
  # was actually set is exactly the bug this avoids.
  def sole_pos_location
    @pos_locations.first if @pos_locations.size == 1
  end

  def remember_pos_location!(location)
    return if location.blank?

    session[:pos_location_id] = location.id
    cookies.permanent.signed[POS_LOCATION_COOKIE] = location.id
  end

  def current_pos_workstation
    return if session[:pos_workstation_id].blank?

    @pos_workstations&.find { |ws| ws.id == session[:pos_workstation_id] } ||
      Workstation.active.find_by(id: session[:pos_workstation_id])
  end
end
