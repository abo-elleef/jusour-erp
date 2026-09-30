# frozen_string_literal: true

# Display name and link for a party. No shared interface exists across
# Supplier#name, Customer#display_name and User#name, so — like
# SettledRecordsHelper for #settles — this has to ask rather than assume.
module PartyHelper
  def party_label(party)
    return nil if party.nil?

    case party
    when Customer then party.display_name
    when Supplier, Partner, User then party.name
    end
  end

  def party_path(party)
    case party
    when Customer then admin_customer_path(party)
    when Supplier  then admin_inventory_supplier_path(party)
    when Partner   then admin_accounting_partner_path(party)
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
