# frozen_string_literal: true

namespace :staff do
  desc "Create and assign a cash drawer treasury for every staff member who does not have one"
  task assign_treasuries: :environment do
    scope = User.unscoped.where(assigned_treasury_id: nil)
    total = scope.count
    if total.zero?
      puts "All staff members already have an assigned treasury."
      next
    end

    created = 0
    failed = 0

    scope.find_each do |user|
      Current.company = user.company
      begin
        treasury = Treasury.create_staff_drawer!(user_name: user.name, company: user.company)
        user.update_column(:assigned_treasury_id, treasury.id)
        created += 1
        puts "Assigned \"#{treasury.name}\" → #{user.name} (#{user.email})"
      rescue StandardError => e
        failed += 1
        warn "Failed for #{user.name} (#{user.email}): #{e.message}"
      end
    end

    puts "Done. Assigned #{created}/#{total} treasury(ies). Failed: #{failed}."
  ensure
    Current.company = nil
  end
end
