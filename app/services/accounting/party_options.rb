# frozen_string_literal: true

module Accounting
  # Options for the party searchable-select: every Supplier, commercial
  # Customer, Partner, Loan and active staff User, tagged with keywords so the
  # picker can be found by kind ("supplier", "staff") as well as by name.
  class PartyOptions
    def self.for_select
      new.to_a
    end

    def to_a
      suppliers + customers + partners + loans + staff
    end

    private

    def suppliers
      Supplier.active.order(:name).map { |s| option(s, s.name, "supplier") }
    end

    # Regular POS customers are walk-ins by the hundred; only commercial
    # (credit) customers are ever the "who" behind a manual expense or income.
    def customers
      Customer.where(customer_type: "commercial").order(:name)
        .map { |c| option(c, c.display_name, "customer") }
    end

    def partners
      Partner.active.order(:name).map { |p| option(p, p.name, "partner") }
    end

    def loans
      Loan.active.ordered.map { |l| option(l, l.name, "loan") }
    end

    def staff
      User.active.order(:name).map { |u| option(u, u.name, "staff employee") }
    end

    def option(record, label, keywords)
      { value: "#{record.class.name}:#{record.id}", label: label, keywords: keywords }
    end
  end
end
