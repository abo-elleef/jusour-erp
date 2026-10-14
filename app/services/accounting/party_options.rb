# frozen_string_literal: true

module Accounting
  # Options for the party searchable-select: every Supplier, commercial
  # Customer, Partner, Loan and active staff User. The type select above this
  # field (shared/_party_picker) already tells the reader what kind they're
  # searching within, so an option doesn't repeat it — the value's own prefix
  # ("Supplier:<id>", "Customer:<id>", ...) is what party-picker filters on.
  class PartyOptions
    def self.for_select
      new.to_a
    end

    def to_a
      suppliers + customers + partners + loans + shipping_companies + staff
    end

    private

    def suppliers
      Supplier.active.order(:name).map { |s| option(s, s.name) }
    end

    # Regular POS customers are walk-ins by the hundred; only commercial
    # (credit) customers are ever the "who" behind a manual expense or income.
    def customers
      Customer.where(customer_type: "commercial").order(:name).map { |c| option(c, c.display_name) }
    end

    def partners
      Partner.active.order(:name).map { |p| option(p, p.name) }
    end

    def loans
      Loan.active.ordered.map { |l| option(l, l.name) }
    end

    def shipping_companies
      ShippingCompany.active.ordered.map { |s| option(s, s.name) }
    end

    def staff
      User.active.order(:name).map { |u| option(u, u.name) }
    end

    def option(record, label)
      { value: "#{record.class.name}:#{record.id}", label: label }
    end
  end
end
