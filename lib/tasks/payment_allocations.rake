# frozen_string_literal: true

# Backfills payment_allocations for supplier payments taken before the table
# existed.
#
#   bin/rails payment_allocations:backfill          # dry run, prints what it would write
#   bin/rails payment_allocations:backfill[commit]  # writes
#
# Supplier payments are exact. A VendorInvoicePayment already belongs to one
# invoice, so its allocation is that invoice for the full amount.
#
# There used to be a customer side here too, reconstructing the FIFO split a
# CustomerPayment never wrote down. Dropped with CustomerPayment itself
# (2026-10-11): production had zero CustomerPayment rows, so there was nothing
# left to replay.
namespace :payment_allocations do
  desc "Backfill payment_allocations from existing supplier payments"
  task :backfill, [:commit] => :environment do |_t, args|
    commit = args[:commit].to_s == "commit"
    warn(commit ? "== WRITING ==" : "== DRY RUN (pass [commit] to write) ==")

    total = 0

    Company.find_each do |company|
      previous = Current.company
      Current.company = company
      begin
        total += backfill_suppliers(company, commit)
      ensure
        Current.company = previous
      end
    end

    warn ""
    warn "supplier allocations: #{total}"
  end

  # ── Suppliers: exact, one allocation per payment ─────────────────────
  def backfill_suppliers(company, commit)
    created = 0
    VendorInvoicePayment.includes(:vendor_invoice).find_each do |payment|
      next if PaymentAllocation.exists?(payment: payment)

      created += 1
      next unless commit

      PaymentAllocation.create!(
        company: company, payment: payment,
        settles: payment.vendor_invoice, amount_cents: payment.amount_cents
      )
    end
    created
  end
end
