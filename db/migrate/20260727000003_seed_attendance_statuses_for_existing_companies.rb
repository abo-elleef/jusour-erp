# frozen_string_literal: true

# Backfill the default P/O/A/X statuses for companies that already exist.
# New companies get them via Company after_create :seed_default_attendance_statuses.
#
# Raw SQL on purpose: a migration must not depend on the AttendanceStatus model,
# whose DEFAULTS/columns evolve in later migrations (e.g. bonus_days is added
# after this one). Seed only the columns that exist at this point in time.
class SeedAttendanceStatusesForExistingCompanies < ActiveRecord::Migration[7.1]
  def up
    execute(<<~SQL)
      INSERT INTO attendance_statuses
        (id, company_id, code, symbol, label, paid_fraction, penalty_days, color, position, active, created_at, updated_at)
      SELECT gen_random_uuid(), c.id, v.code, v.symbol, v.label, v.paid_fraction, v.penalty_days, v.color, v.position, TRUE, NOW(), NOW()
      FROM companies c
      CROSS JOIN (VALUES
        ('present',   'P', 'Present',           1, 0, 'emerald', 1),
        ('off',       'O', 'Planned off',       1, 0, 'blue',    2),
        ('excused',   'A', 'Excused absence',   1, 0, 'amber',   3),
        ('unexcused', 'X', 'Unexcused absence', 0, 1, 'red',     4)
      ) AS v(code, symbol, label, paid_fraction, penalty_days, color, position)
      ON CONFLICT (company_id, code) DO NOTHING;
    SQL
  end

  def down
    # Leave the seeded rows in place.
  end
end
