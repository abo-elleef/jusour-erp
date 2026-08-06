# frozen_string_literal: true

# Audited's install generator only customizes user_id type; our models use UUID PKs.
class ChangeAuditsPolymorphicIdsToUuid < ActiveRecord::Migration[7.1]
  def up
    change_column :audits, :auditable_id, :uuid, using: "NULL"
    change_column :audits, :associated_id, :uuid, using: "NULL"
  end

  def down
    change_column :audits, :auditable_id, :integer, using: "NULL"
    change_column :audits, :associated_id, :integer, using: "NULL"
  end
end
