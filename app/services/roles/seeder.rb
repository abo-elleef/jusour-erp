# frozen_string_literal: true

module Roles
  # Seeds a company's built-in roles from the Permission catalog. Idempotent and
  # NON-destructive: it only creates roles that are missing, so it never wipes an
  # owner's customised permissions. Runs on company creation and can be re-run to
  # backfill newly-introduced built-in roles.
  class Seeder
    def self.call(company)
      Permission::BUILTIN_ROLES.each do |key, config|
        role = Role.unscoped.find_or_initialize_by(company_id: company.id, key: key)
        next unless role.new_record?

        role.name = config[:name]
        role.built_in = true
        role.permissions = config[:permissions]
        role.save!
      end
    end
  end
end
