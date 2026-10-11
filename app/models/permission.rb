# frozen_string_literal: true

# The catalog of tab/section-level capabilities the app checks. This is the
# SOURCE OF TRUTH for *what permissions exist* — code must know which keys it
# checks. *Which role has which permission* lives in the DB (roles.permissions),
# so owners can customise per company.
#
# Checks are always `current_user.can?("accounting:reports")` — never role names.
module Permission
  # key   — the capability string checked in code
  # group — for grouping in the (future) role-editor UI
  CATALOG = [
    { key: "dashboard:view",          group: "operations" },
    { key: "orders:view",             group: "operations" },
    { key: "orders:refund",           group: "operations" },
    { key: "menu:manage",             group: "operations" },
    { key: "customers:manage",        group: "operations" },

    { key: "inventory:view",          group: "inventory" },
    { key: "inventory:manage",        group: "inventory" },
    { key: "inventory:settings",      group: "inventory" },
    { key: "inventory:finance",       group: "inventory" },
    { key: "inventory:manufacturing", group: "inventory" },

    { key: "accounting:ledgers",      group: "accounting" },
    { key: "accounting:transactions", group: "accounting" },
    { key: "accounting:reports",      group: "accounting" },
    { key: "accounting:day_close",    group: "accounting" },
    { key: "accounting:setup",        group: "accounting" },
    { key: "accounting:audit",        group: "accounting" },

    { key: "attendance:log",          group: "staff" },
    { key: "attendance:view",         group: "staff" },
    { key: "attendance:penalties",     group: "staff" },
    { key: "attendance:waive_penalties", group: "staff" },
    { key: "attendance:audit",        group: "staff" },
    { key: "staff:view",              group: "staff" },
    { key: "staff:manage",            group: "staff" },
    { key: "payroll:view",            group: "staff" },
    { key: "payroll:manage",          group: "staff" },

    { key: "settings:general",        group: "settings" },
    { key: "locations:manage",        group: "settings" },
    { key: "printers:manage",         group: "settings" },
    { key: "integrations:manage",     group: "settings" },
    { key: "payments:manage",         group: "settings" },

    { key: "pos:access",              group: "apps" },
    { key: "kitchen:access",          group: "apps" },
    { key: "production:access",       group: "apps" },

    { key: "leads:view",              group: "sales" },
    { key: "leads:manage",            group: "sales" },
    { key: "leads:reports",           group: "sales" }
  ].freeze

  KEYS = CATALOG.map { |p| p[:key] }.freeze
  GROUPS = CATALOG.map { |p| p[:group] }.uniq.freeze

  # Seeded defaults for the built-in roles. Owners can edit these per company
  # afterwards (that's the whole point of DB-backed roles) — these are just the
  # starting point. `key` marks them as system roles.
  BUILTIN_ROLES = {
    "owner" => {
      name: "Owner",
      permissions: KEYS # full access
    },
    "super_manager" => {
      name: "Super manager",
      # broad, minus owner-only fiscal config
      permissions: KEYS - %w[integrations:manage payments:manage accounting:audit]
    },
    "manager" => {
      name: "Manager",
      permissions: %w[
        dashboard:view orders:view orders:refund menu:manage customers:manage
        inventory:view inventory:manage inventory:settings inventory:manufacturing
        accounting:transactions accounting:day_close accounting:reports
        attendance:log attendance:view attendance:penalties attendance:waive_penalties attendance:audit staff:view locations:manage printers:manage
        pos:access kitchen:access production:access
        leads:view leads:manage leads:reports
      ]
    },
    "sub_manager" => {
      name: "Sub-manager",
      # Runs the floor, logs attendance, and closes out the day's drawers — but no
      # other accounting: recording spend stays with the roles above.
      permissions: %w[
        dashboard:view orders:view menu:manage customers:manage inventory:view
        accounting:day_close
        attendance:log attendance:view pos:access kitchen:access
        leads:view leads:manage
      ]
    },
    "accountant" => {
      name: "Accountant",
      permissions: %w[
        dashboard:view orders:view inventory:view inventory:finance inventory:manufacturing
        accounting:ledgers accounting:transactions accounting:day_close accounting:reports accounting:setup
        attendance:view attendance:penalties attendance:waive_penalties staff:view staff:manage payroll:view payroll:manage
        settings:general locations:manage printers:manage pos:access
      ]
    },
    "cashier" => {
      name: "Cashier",
      permissions: %w[pos:access]
    },
    "kitchen" => {
      name: "Kitchen",
      permissions: %w[kitchen:access production:access]
    }
  }.freeze

  def self.valid?(key)
    KEYS.include?(key.to_s)
  end
end
