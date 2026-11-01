# frozen_string_literal: true

module LedgerReportsHelper
  # A debit-positive balance in one of a debit/credit column pair: the amount
  # when it falls on that side, a faint dash otherwise.
  def ledger_side_amount(cents, side)
    amount = side == :debit ? cents : -cents
    return tag.span("–", class: "text-gray-300") unless amount.positive?

    format_amount(amount)
  end

  # A debit-positive running balance as one figure with its side spelled out.
  def ledger_balance(cents)
    return format_amount(0) if cents.zero?

    side = cents.positive? ? t("accounting.ledger.dr") : t("accounting.ledger.cr")
    safe_join([format_amount(cents.abs), " ", tag.span(side, class: "text-xs text-gray-500")])
  end
end
