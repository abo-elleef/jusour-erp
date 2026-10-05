# frozen_string_literal: true

module Accounting
  # Options for the party searchable-select: every Supplier, commercial
  # Customer, Partner, Loan and active staff User. Each option carries its kind
  # twice over: as a keyword (so typing "supplier" or "مورد" filters to just
  # those) and as an alias (the searchable-select JS already renders aliases as
  # a muted line under the name) — without it, a bare list of names gives no
  # hint whether "محمود طه" is a supplier or a staff member.
  class PartyOptions
    def self.for_select
      new.to_a
    end

    def to_a
      suppliers + customers + partners + loans + staff
    end

    private

    def suppliers
      kind = I18n.t("accounting.shared.party_kinds.supplier")
      Supplier.active.order(:name).map { |s| option(s, s.name, "supplier #{kind}", kind) }
    end

    # Regular POS customers are walk-ins by the hundred; only commercial
    # (credit) customers are ever the "who" behind a manual expense or income.
    def customers
      kind = I18n.t("accounting.shared.party_kinds.customer")
      Customer.where(customer_type: "commercial").order(:name)
        .map { |c| option(c, c.display_name, "customer #{kind}", kind) }
    end

    def partners
      kind = I18n.t("accounting.shared.party_kinds.partner")
      Partner.active.order(:name).map { |p| option(p, p.name, "partner #{kind}", kind) }
    end

    def loans
      kind = I18n.t("accounting.shared.party_kinds.loan")
      Loan.active.ordered.map { |l| option(l, l.name, "loan #{kind}", kind) }
    end

    def staff
      kind = I18n.t("accounting.shared.party_kinds.staff")
      User.active.order(:name).map { |u| option(u, u.name, "staff employee #{kind}", kind) }
    end

    def option(record, label, keywords, kind)
      { value: "#{record.class.name}:#{record.id}", label: label, keywords: keywords, aliases: [kind] }
    end
  end
end
