# frozen_string_literal: true

class CreateRolesAndBackfill < ActiveRecord::Migration[7.1]
  # Point-in-time snapshot of the built-in role → permission defaults. Kept
  # literal (not read from Permission::*) so this migration stays reproducible
  # and uses only raw SQL, no app models.
  ALL = %w[
    dashboard:view orders:view orders:refund menu:manage customers:manage
    inventory:view inventory:manage
    accounting:ledgers accounting:transactions accounting:reports accounting:setup accounting:audit
    attendance:log attendance:view staff:view staff:manage payroll:view payroll:manage
    settings:general locations:manage printers:manage integrations:manage payments:manage
    pos:access kitchen:access production:access
  ].freeze

  ROLE_SEEDS = {
    "owner"         => ["Owner",         ALL],
    "super_manager" => ["Super manager", ALL - %w[integrations:manage payments:manage accounting:audit]],
    "manager"       => ["Manager",       %w[dashboard:view orders:view orders:refund menu:manage customers:manage inventory:view inventory:manage accounting:transactions accounting:reports attendance:log attendance:view staff:view locations:manage printers:manage pos:access kitchen:access production:access]],
    "sub_manager"   => ["Sub-manager",   %w[dashboard:view orders:view menu:manage customers:manage inventory:view attendance:log attendance:view pos:access kitchen:access]],
    "accountant"    => ["Accountant",    %w[dashboard:view orders:view inventory:view accounting:ledgers accounting:transactions accounting:reports accounting:setup attendance:view staff:view staff:manage payroll:view payroll:manage settings:general locations:manage printers:manage pos:access]],
    "cashier"       => ["Cashier",       %w[pos:access orders:view]],
    "kitchen"       => ["Kitchen",       %w[kitchen:access production:access]]
  }.freeze

  def up
    create_table :roles, id: :uuid do |t|
      t.uuid    :company_id, null: false
      t.string  :key
      t.string  :name, null: false
      t.jsonb   :permissions, null: false, default: []
      t.boolean :built_in, null: false, default: false
      t.timestamps
    end
    add_index :roles, %i[company_id key], unique: true, where: "key IS NOT NULL"
    add_index :roles, :company_id

    add_column :users, :role_id, :uuid
    add_index :users, :role_id

    # Seed built-in roles for every existing company (one statement per role).
    ROLE_SEEDS.each do |key, (name, perms)|
      execute(<<~SQL.squish)
        INSERT INTO roles (id, company_id, key, name, permissions, built_in, created_at, updated_at)
        SELECT gen_random_uuid(), c.id, #{quote(key)}, #{quote(name)}, #{quote(perms.to_json)}::jsonb, true, now(), now()
        FROM companies c
      SQL
    end

    # Backfill users.role_id from their existing string role.
    execute(<<~SQL.squish)
      UPDATE users u SET role_id = r.id
      FROM roles r
      WHERE r.company_id = u.company_id AND r.key = u.role
    SQL

    add_foreign_key :users, :roles, column: :role_id
  end

  def down
    remove_foreign_key :users, column: :role_id
    remove_column :users, :role_id
    drop_table :roles
  end
end
