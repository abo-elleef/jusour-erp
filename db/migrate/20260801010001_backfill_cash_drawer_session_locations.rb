# frozen_string_literal: true

class BackfillCashDrawerSessionLocations < ActiveRecord::Migration[7.1]
  def up
    say_with_time "Backfill cash_drawer_sessions.location_id" do
      CashDrawerSession.reset_column_information
      CashDrawerSession.where(location_id: nil).find_each do |session|
        user = session.user
        next unless user

        location =
          user.locations.find_by(location_type: "branch", active: true) ||
          Location.where(company_id: user.company_id, location_type: "branch", active: true).order(:position, :name).first

        session.update_columns(location_id: location.id) if location
      end
    end
  end

  def down
    # irreversible data backfill
  end
end
