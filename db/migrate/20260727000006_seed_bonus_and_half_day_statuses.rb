# frozen_string_literal: true

# Add the new PP (present + bonus) and H (half day) statuses to existing
# companies. seed_defaults! is idempotent — it only creates missing codes.
class SeedBonusAndHalfDayStatuses < ActiveRecord::Migration[7.1]
  def up
    Company.reset_column_information
    Company.find_each { |company| AttendanceStatus.seed_defaults!(company) }
  end

  def down
    # Leave the seeded rows in place.
  end
end
