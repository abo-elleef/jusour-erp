# frozen_string_literal: true

# Why a document's Edit button is disabled, worded for the tooltip edit_button
# shows. Each returns nil when the current user can edit the record.
module EditBlockedHelper
  def vendor_invoice_edit_blocked_message(invoice)
    return t("edit_blocked.no_permission") unless can_manage_inventory_stock?

    case invoice.edit_blocked_reason
    when :void
      t("edit_blocked.vendor_invoice.void")
    when :credit_applied
      numbers = invoice.vendor_credit_notes.confirmed.order(:credit_note_number).pluck(:credit_note_number)
      t("edit_blocked.vendor_invoice.credit_applied", numbers: numbers.to_sentence)
    when :historical_settled
      t("edit_blocked.vendor_invoice.historical_settled")
    end
  end

  def customer_invoice_edit_blocked_message(invoice)
    return if invoice.draft?

    t("edit_blocked.customer_invoice.#{invoice.status}")
  end

  # Credit notes have no edit screen at all, so every state carries a reason.
  def vendor_credit_note_edit_blocked_message(credit_note)
    t("edit_blocked.vendor_credit_note.#{credit_note.status}")
  end

  def customer_credit_note_edit_blocked_message(credit_note)
    t("edit_blocked.customer_credit_note.#{credit_note.status}")
  end
end
