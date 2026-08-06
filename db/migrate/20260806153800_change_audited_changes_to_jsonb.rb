# frozen_string_literal: true

# Text + YAML cannot safely dump Date/Time under Psych.safe_dump (Ruby 3.1+).
# JSONB stores audited_changes as JSON and handles dates cleanly.
class ChangeAuditedChangesToJsonb < ActiveRecord::Migration[7.1]
  def up
    change_column :audits, :audited_changes, :jsonb, using: "NULL"
  end

  def down
    change_column :audits, :audited_changes, :text
  end
end
