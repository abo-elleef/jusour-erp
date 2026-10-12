# frozen_string_literal: true

# Backfills a newly-introduced built-in permission onto existing companies.
#
# `Roles::Seeder` is deliberately non-destructive — it only creates roles that are
# missing, so it never wipes an owner's customisations. That also means adding a
# key to `Permission::BUILTIN_ROLES` does nothing for companies whose roles already
# exist, which is what this covers.
#
#   bin/rails roles:grant_day_close
#
# Safe to re-run: a role that already has the key is left alone.
namespace :roles do
  # accounting:day_close is a rule of its own — it is deliberately NOT implied by
  # accounting:transactions, which is about expenses, incomes and treasuries. So
  # every role that should close a day needs the key granted explicitly.
  DAY_CLOSE_ROLE_KEYS = %w[owner super_manager manager sub_manager accountant].freeze

  desc "Give existing built-in roles the accounting:day_close permission"
  task grant_day_close: :environment do
    key = "accounting:day_close"
    granted = 0
    skipped = 0

    Role.unscoped.where(key: DAY_CLOSE_ROLE_KEYS).find_each do |role|
      if role.permission_keys.include?(key)
        skipped += 1
        next
      end

      role.permissions = role.permission_keys + [key]
      role.save!
      granted += 1
    end

    puts "Granted #{key} to #{granted} role(s); #{skipped} already had it."
  end

  # Mirrors Permission::BUILTIN_ROLES' leads:* entries (added alongside the Lead
  # model) — see that file for which role gets which key.
  LEADS_FULL_ROLE_KEYS = %w[owner super_manager manager].freeze
  LEADS_BASIC_ROLE_KEYS = %w[sub_manager].freeze

  desc "Give existing built-in roles the new leads:view/manage/reports permissions"
  task grant_leads_permissions: :environment do
    granted = 0
    skipped = 0

    grant = lambda do |role_keys, keys|
      Role.unscoped.where(key: role_keys).find_each do |role|
        missing = keys - role.permission_keys
        if missing.empty?
          skipped += 1
          next
        end

        role.permissions = role.permission_keys + missing
        role.save!
        granted += 1
      end
    end

    grant.call(LEADS_FULL_ROLE_KEYS, %w[leads:view leads:manage leads:reports])
    grant.call(LEADS_BASIC_ROLE_KEYS, %w[leads:view leads:manage])

    puts "Updated #{granted} role(s); #{skipped} already had their leads permissions."
  end
end
