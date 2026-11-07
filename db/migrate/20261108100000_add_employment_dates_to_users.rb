# frozen_string_literal: true

# When someone started and stopped being on payroll, so the monthly payroll
# page can show only people employed in the month being viewed.
class AddEmploymentDatesToUsers < ActiveRecord::Migration[7.1]
  def up
    add_column :users, :employment_start_on, :date
    add_column :users, :employment_end_on, :date
    add_index :users, :employment_start_on
    add_index :users, :employment_end_on

    # Raw SQL: no app models in migrations.
    execute <<~SQL.squish
      UPDATE users SET employment_start_on = created_at::date
    SQL
    # Staff entered after they actually started: first payroll record wins.
    execute <<~SQL.squish
      UPDATE users SET employment_start_on = s.first_month
      FROM (SELECT user_id, MIN(payroll_month) AS first_month FROM payroll_snapshots GROUP BY user_id) s
      WHERE s.user_id = users.id AND s.first_month < users.employment_start_on
    SQL
    # Best guess for people already deactivated; editable on the staff form.
    execute <<~SQL.squish
      UPDATE users SET employment_end_on = updated_at::date WHERE active = false
    SQL
  end

  def down
    remove_column :users, :employment_end_on
    remove_column :users, :employment_start_on
  end
end
