# frozen_string_literal: true

# Backfills payment_allocations for payments taken before the table existed.
#
#   bin/rails payment_allocations:backfill          # dry run, prints what it would write
#   bin/rails payment_allocations:backfill[commit]  # writes
#
# The two sides are not equally knowable:
#
#   Supplier payments are exact. A VendorInvoicePayment already belongs to one
#   invoice, so its allocation is that invoice for the full amount.
#
#   Customer payments are a reconstruction. A CustomerPayment belongs to a
#   customer, not an invoice, and the FIFO split was never written down — only
#   the resulting amount_paid_cents on each invoice survives. The replay below
#   re-runs the same oldest-first rule over each customer's invoices in payment
#   order, which reproduces what the code did whenever invoices and payments
#   were interleaved in the obvious way. Where it cannot, the task says so per
#   invoice instead of writing a confident wrong number.
namespace :payment_allocations do
  desc "Backfill payment_allocations from existing customer and supplier payments"
  task :backfill, [:commit] => :environment do |_t, args|
    commit = args[:commit].to_s == "commit"
    warn(commit ? "== WRITING ==" : "== DRY RUN (pass [commit] to write) ==")

    totals = Hash.new(0)
    mismatches = []

    Company.find_each do |company|
      previous = Current.company
      Current.company = company
      begin
        totals[:suppliers] += backfill_suppliers(company, commit)
        created, bad = backfill_customers(company, commit)
        totals[:customers] += created
        mismatches.concat(bad)
      ensure
        Current.company = previous
      end
    end

    warn ""
    warn "supplier allocations: #{totals[:suppliers]}"
    warn "customer allocations: #{totals[:customers]}"

    if mismatches.any?
      warn ""
      warn "#{mismatches.size} invoice(s) the replay could not reproduce exactly:"
      mismatches.first(50).each { |m| warn "  #{m}" }
      warn "  … #{mismatches.size - 50} more" if mismatches.size > 50
      warn ""
      warn "These are invoices whose amount_paid_cents does not match the FIFO"
      warn "replay — most often because an invoice was confirmed after a payment"
      warn "that later settled it. Allocations were still written; the difference"
      warn "is the part no surviving record can attribute."
    end
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

  # ── Customers: FIFO replay ───────────────────────────────────────────
  def backfill_customers(company, commit)
    created = 0
    mismatches = []

    Customer.find_each do |customer|
      payments = CustomerPayment.where(customer: customer)
                                .order(:payment_date, :created_at).to_a
      next if payments.empty?
      # Idempotent per customer: a half-replayed customer would collide with
      # the unique index, so one already-allocated payment skips the whole set.
      next if payments.any? { |p| PaymentAllocation.exists?(payment: p) }

      invoices = CustomerInvoice.where(customer: customer, status: "confirmed")
                                .order(:invoice_date, :created_at).to_a
      # How much of each invoice the replay has consumed so far.
      filled = Hash.new(0)

      payments.each do |payment|
        remaining = payment.amount_cents
        invoices.each do |invoice|
          break if remaining <= 0

          room = invoice.total_cents - filled[invoice.id]
          applied = [room, remaining].min
          next if applied <= 0

          filled[invoice.id] += applied
          remaining -= applied
          created += 1
          next unless commit

          PaymentAllocation.create!(
            company: company, payment: payment,
            settles: invoice, amount_cents: applied
          )
        end
      end

      invoices.each do |invoice|
        next if filled[invoice.id] == invoice.amount_paid_cents

        mismatches << "#{invoice.invoice_number}  replay=#{filled[invoice.id]}  " \
                      "recorded=#{invoice.amount_paid_cents}  (#{customer.display_name})"
      end
    end

    [created, mismatches]
  end
end
