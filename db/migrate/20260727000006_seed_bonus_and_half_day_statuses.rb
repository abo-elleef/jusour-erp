# frozen_string_literal: true

# Add the PP (present + bonus) and H (half day) statuses to existing companies.
# Raw SQL (not the model) so it stays valid regardless of how AttendanceStatus's
# DEFAULTS evolve later. bonus_days exists by now (added in ...000005).
class SeedBonusAndHalfDayStatuses < ActiveRecord::Migration[7.1]
  def up
    execute(<<~SQL)
      INSERT INTO attendance_statuses
        (id, company_id, code, symbol, label, paid_fraction, bonus_days, penalty_days, color, position, active, created_at, updated_at)
      SELECT gen_random_uuid(), c.id, v.code, v.symbol, v.label, v.paid_fraction, v.bonus_days, v.penalty_days, v.color, v.position, TRUE, NOW(), NOW()
      FROM companies c
      CROSS JOIN (VALUES
        ('present_bonus', 'PP', 'Present + bonus', 1,   1, 0, 'teal',   2),
        ('half_day',      'H',  'Half day',        0.5, 0, 0, 'indigo', 4)
      ) AS v(code, symbol, label, paid_fraction, bonus_days, penalty_days, color, position)
      ON CONFLICT (company_id, code) DO NOTHING;
    SQL
  end

  def down
    # Leave the seeded rows in place.
  end
end
