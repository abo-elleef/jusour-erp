# frozen_string_literal: true

# Gives each unassigned customer a salesperson (customers.assigned_user_id), so
# reps limited by Sales::OwnershipScope keep seeing the customers they already
# work with once sales:see_all is taken off their role.
#
#   1. The salesperson on the customer's most recent non-void invoice that
#      names one.
#   2. Otherwise the assigned user of the lead the customer was converted from.
#   3. Otherwise the customer stays unassigned (managers only, until assigned).
#
# Only companies running the sales area (credit sales or leads). Never
# overwrites an existing assignment.
#
#   DRY_RUN=1 bin/rails sales:backfill_customer_owners                 # counts only, writes nothing
#   bin/rails sales:backfill_customer_owners                           # write
#   COMPANY=<slug-or-id> DRY_RUN=1 bin/rails sales:backfill_customer_owners
#
# Read-only SQL for the plan, so a dry run also works on a database that
# hasn't been migrated yet (it then treats every customer as unassigned).
namespace :sales do
  desc "Assign each unassigned customer to a salesperson (DRY_RUN=1 for counts only)"
  task backfill_customer_owners: :environment do
    dry_run = ENV["DRY_RUN"].present?
    conn = ActiveRecord::Base.connection
    migrated = conn.column_exists?(:customers, :assigned_user_id)
    unless migrated || dry_run
      abort "customers.assigned_user_id is missing — run db:migrate first (or pass DRY_RUN=1)."
    end

    companies = Company.unscoped.order(:name)
    if (key = ENV["COMPANY"].presence)
      companies = key.match?(/\A\h{8}-\h{4}-/) ? companies.where(id: key) : companies.where(slug: key)
    end
    companies = companies.select { |company| Sales::OwnershipScope.applies_to?(company) }
    abort "No company with the sales area matched." if companies.empty?

    puts(dry_run ? "DRY RUN — nothing will be written." : "Writing assignments.")
    puts "(customers.assigned_user_id not migrated here — every customer counted as unassigned.)" unless migrated

    companies.each do |company|
      unassigned_filter = migrated ? "AND c.assigned_user_id IS NULL" : ""
      plan_sql = <<~SQL.squish
        SELECT c.id AS customer_id,
               inv.salesperson_id AS invoice_user_id,
               ld.assigned_user_id AS lead_user_id
        FROM customers c
        LEFT JOIN LATERAL (
          SELECT ci.salesperson_id FROM customer_invoices ci
          WHERE ci.customer_id = c.id AND ci.status <> 'void' AND ci.salesperson_id IS NOT NULL
          ORDER BY ci.invoice_date DESC, ci.created_at DESC
          LIMIT 1
        ) inv ON TRUE
        LEFT JOIN LATERAL (
          SELECT l.assigned_user_id FROM leads l
          WHERE l.company_id = c.company_id AND (l.id = c.originating_lead_id OR l.customer_id = c.id)
          ORDER BY l.converted_at DESC NULLS LAST, l.created_at DESC
          LIMIT 1
        ) ld ON TRUE
        WHERE c.company_id = #{conn.quote(company.id)} #{unassigned_filter}
      SQL
      rows = conn.select_all(plan_sql).to_a
      users = User.unscoped.where(company_id: company.id).pluck(:id, :name, :active).to_h { |id, name, active| [id, [name, active]] }

      plan = Hash.new { |h, k| h[k] = [] }
      from_invoice = from_lead = 0
      rows.each do |row|
        user_id = row["invoice_user_id"] || row["lead_user_id"]
        next unless user_id && users.key?(user_id)

        row["invoice_user_id"] ? from_invoice += 1 : from_lead += 1
        plan[user_id] << row["customer_id"]
      end
      staying = rows.size - plan.values.sum(&:size)

      puts "\n#{company.name} (#{company.slug}) — #{rows.size} unassigned customer(s)"
      plan.sort_by { |user_id, ids| [-ids.size, users[user_id][0].to_s] }.each do |user_id, ids|
        name, active = users[user_id]
        puts format("  %-40s %6d%s", name, ids.size, active ? "" : "  (inactive user)")
      end
      puts "  from latest invoice's salesperson: #{from_invoice}; from converting lead: #{from_lead}"
      puts "  staying unassigned: #{staying}"

      next if dry_run

      ActiveRecord::Base.transaction do
        plan.each do |user_id, ids|
          ids.each_slice(1000) do |slice|
            conn.execute(<<~SQL.squish)
              UPDATE customers SET assigned_user_id = #{conn.quote(user_id)}, updated_at = NOW()
              WHERE assigned_user_id IS NULL AND id IN (#{slice.map { |id| conn.quote(id) }.join(', ')})
            SQL
          end
        end
      end
      puts "  written."
    end
  end
end
