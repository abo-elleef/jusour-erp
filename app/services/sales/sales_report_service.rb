# frozen_string_literal: true

module Sales
  # What a distributor sold over a period: totals, and the same figures broken down
  # by product, by customer and by salesperson, with returns netted off throughout.
  #
  # Reads the sales documents directly rather than the ledger — the ledger knows what
  # was earned but has no product, customer or salesperson dimension. It counts every
  # *realized* document: confirmed sales made in this system, and historical ones
  # imported from the previous system, which really happened and belong in the totals
  # even though they never touched the ledger or stock.
  class SalesReportService
    Row = Struct.new(:key, :name, :units, :revenue_cents, :returns_cents, keyword_init: true) do
      def net_cents = revenue_cents - returns_cents
    end

    def initialize(start_date, end_date, customer_type: nil)
      @start_date = start_date
      @end_date = end_date
      @customer_type = customer_type if Customer::CUSTOMER_TYPES.include?(customer_type)
    end

    # Computes every breakdown at once. Prefer calling the individual methods
    # below directly when only one is needed (e.g. one report tab lazy-loaded on
    # its own) — by_product/by_customer can run into thousands of rows, so
    # computing all of them on every request doesn't scale.
    def call
      {
        summary: summary,
        by_product: by_product,
        by_customer: by_customer,
        by_salesperson: by_salesperson,
        by_payment_method: by_payment_method,
        daily: daily
      }
    end

    def summary
      count = invoices.count
      {
        invoice_count: count,
        credit_note_count: credit_notes.count,
        gross_sales_cents: gross_cents,
        returns_cents: returns_cents,
        net_sales_cents: gross_cents - returns_cents,
        customer_count: invoices.distinct.count(:customer_id),
        average_invoice_cents: count.positive? ? (gross_cents / count) : 0,
        forgone_delivery_fee_cents: forgone_delivery_fee_cents
      }
    end

    # Delivery-fee revenue given up to the free-delivery promo: the courier is
    # still paid their standard cut in full (see
    # Accounting::ShippingCompanyLedgerService#accrue_delivery_fee!) — this is
    # purely what Bazzar chose not to bill the customer for.
    def forgone_delivery_fee_cents
      @forgone_delivery_fee_cents ||=
        invoices.where(fulfillment_method: "delivery")
          .sum("standard_delivery_fee_cents - delivery_fee_cents").to_i
    end

    # Units and money per product, with returned units and money subtracted so a
    # product that was mostly sent back doesn't look like a bestseller.
    def by_product
      sold = CustomerInvoiceLine.where(customer_invoice_id: invoices.select(:id))
        .joins(:ingredient)
        .group("ingredients.id", "ingredients.name")
        .pluck(Arel.sql("ingredients.id"), Arel.sql("ingredients.name"),
               Arel.sql("SUM(customer_invoice_lines.quantity)"),
               Arel.sql("SUM(customer_invoice_lines.line_total_cents)"))

      returned = CreditNoteLine.where(credit_note_id: credit_notes.select(:id))
        .group(:ingredient_id)
        .pluck(Arel.sql("ingredient_id"),
               Arel.sql("SUM(quantity)"),
               Arel.sql("SUM(line_total_cents)"))
        .to_h { |id, units, cents| [id, [units.to_d, cents.to_i]] }

      rows = sold.map do |id, name, units, cents|
        back_units, back_cents = returned.fetch(id, [0, 0])
        Row.new(key: id, name: name, units: units.to_d - back_units,
                revenue_cents: cents.to_i, returns_cents: back_cents)
      end

      # A product only ever returned in this period still belongs in the list.
      (returned.keys - sold.map(&:first)).each do |id|
        back_units, back_cents = returned[id]
        rows << Row.new(key: id, name: Ingredient.find_by(id: id)&.name.to_s,
                        units: -back_units, revenue_cents: 0, returns_cents: back_cents)
      end

      rows.sort_by { |r| -r.net_cents }
    end

    def by_customer
      returned = credit_notes.group(:customer_id).sum(:total_cents)

      rows = invoices.joins(:customer).group("customers.id", "customers.name")
        .pluck(Arel.sql("customers.id"), Arel.sql("customers.name"),
               Arel.sql("COUNT(*)"), Arel.sql("SUM(total_cents)"))
        .map do |id, name, count, cents|
          Row.new(key: id, name: name, units: count.to_i,
                  revenue_cents: cents.to_i, returns_cents: returned[id].to_i)
        end

      rows.sort_by { |r| -r.net_cents }
    end

    # Credited to the teammate the sale is attributed to, which is not always whoever
    # keyed it in. Invoices with nobody attributed are grouped under a blank name.
    def by_salesperson
      invoices.left_joins(:salesperson).group("users.id", "users.name")
        .pluck(Arel.sql("users.id"), Arel.sql("users.name"),
               Arel.sql("COUNT(*)"), Arel.sql("SUM(customer_invoices.total_cents)"))
        .map { |id, name, count, cents|
          Row.new(key: id, name: name.to_s, units: count.to_i,
                  revenue_cents: cents.to_i, returns_cents: 0)
        }
        .sort_by { |r| -r.revenue_cents }
    end

    # How the money came in: on account (still owed, or settled later against the
    # customer's balance) versus taken at the counter by cash or wallet.
    def by_payment_method
      counts = invoices.group(:payment_method).count
      totals = invoices.group(:payment_method).sum(:total_cents)

      CustomerInvoice::PAYMENT_METHODS.filter_map do |method|
        total = totals[method].to_i
        next if total.zero? && counts[method].to_i.zero?

        Row.new(key: method, name: method, units: counts[method].to_i,
                revenue_cents: total, returns_cents: 0)
      end.sort_by { |r| -r.revenue_cents }
    end

    def daily
      sold = invoices.group(:invoice_date).sum(:total_cents)
      back = credit_notes.group(:credit_note_date).sum(:total_cents)

      (@start_date..@end_date).filter_map do |date|
        gross = sold[date].to_i
        returned = back[date].to_i
        next if gross.zero? && returned.zero?

        { date: date, gross_cents: gross, returns_cents: returned, net_cents: gross - returned }
      end
    end

    # A cheap check for whether "by payment method" is worth its own tab — just
    # how many distinct methods appear, not the full breakdown.
    def payment_method_variety
      invoices.distinct.count(:payment_method)
    end

    private

    def invoices
      @invoices ||= scoped_to_customer_type(CustomerInvoice.realized.where(invoice_date: @start_date..@end_date))
    end

    def credit_notes
      @credit_notes ||= scoped_to_customer_type(CreditNote.realized.where(credit_note_date: @start_date..@end_date))
    end

    # Lets the owner read the same report as three different audiences: everyone,
    # commercial (credit) buyers only, or regular (cash) customers only — a
    # commercial account's bulk orders otherwise bury a doctor's own top spot in
    # every breakdown.
    def scoped_to_customer_type(relation)
      return relation unless @customer_type

      relation.joins(:customer).where(customers: { customer_type: @customer_type })
    end

    def gross_cents  = @gross_cents  ||= invoices.sum(:total_cents).to_i
    def returns_cents = @returns_cents ||= credit_notes.sum(:total_cents).to_i
  end
end
