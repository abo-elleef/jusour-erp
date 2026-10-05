# frozen_string_literal: true

# Display name and link for a party. No shared interface exists across
# Supplier#name, Customer#display_name and User#name, so — like
# SettledRecordsHelper for #settles — this has to ask rather than assume.
module PartyHelper
  # A bare name is ambiguous on its own — "محمود طه" gives no hint whether
  # that's a supplier, a staff member, or a partner. party_label always
  # appends the kind for that reason; call party_bare_name directly only
  # where the kind is already obvious from context (e.g. next to a column
  # header that already says "Supplier").
  def party_bare_name(party)
    case party
    when Customer then party.display_name
    when Supplier, Partner, User, Loan then party.name
    end
  end

  def party_kind_label(party)
    case party
    when Supplier then t("accounting.shared.party_kinds.supplier")
    when Customer then t("accounting.shared.party_kinds.customer")
    when Partner  then t("accounting.shared.party_kinds.partner")
    when Loan     then t("accounting.shared.party_kinds.loan")
    when User     then t("accounting.shared.party_kinds.staff")
    end
  end

  def party_label(party)
    return nil if party.nil?

    name = party_bare_name(party)
    return nil if name.nil?

    kind = party_kind_label(party)
    kind ? "#{name} — #{kind}" : name
  end

  def party_path(party)
    case party
    when Customer then admin_customer_path(party)
    when Supplier  then admin_inventory_supplier_path(party)
    when Partner   then admin_accounting_partner_path(party)
    when Loan      then admin_accounting_loan_path(party)
    when User      then admin_user_path(party)
    end
  end

  # Link when there is somewhere to go, plain text otherwise — same shape as
  # SettledRecordsHelper#settled_link.
  def party_link(party, **options)
    label = party_label(party)
    return nil if label.nil?

    path = party_path(party)
    path ? link_to(label, path, **options) : content_tag(:span, label, **options)
  end

  # What a voucher's "who" actually is. Priority: the party behind whatever it
  # settled (an invoice already names its supplier, an advance its employee) —
  # so a settlement voucher never asks the issuer to retype a name the system
  # already has — then the voucher's own manually-picked party, used for
  # equity adjustments and on-account movements that settle nothing. A voucher
  # settling several things is assumed to settle them all with the same party,
  # which holds for every flow that writes more than one allocation today.
  def voucher_party(voucher)
    settled = voucher.payment_allocations.first&.settles
    settled_party(settled) || voucher.party
  end

  def voucher_party_label(voucher)
    party_label(voucher_party(voucher)) || voucher.counterparty.presence
  end

  # Link when the derived or picked party has a page of its own; otherwise the
  # legacy free-text counterparty as plain text, otherwise nil.
  def voucher_party_link(voucher)
    party = voucher_party(voucher)
    return party_link(party) if party

    voucher.counterparty.presence
  end
end
