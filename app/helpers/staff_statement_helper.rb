# frozen_string_literal: true

module StaffStatementHelper
  # Whose favour a staff account balance is in. Positive is owed to them.
  def staff_balance_label(cents)
    if cents.positive? then t("staff.wages_ledger.owed_to_them")
    elsif cents.negative? then t("staff.wages_ledger.they_owe")
    else t("staff.wages_ledger.settled")
    end
  end

  # Balances keep their sign on the statement so a debt reads as one.
  def staff_signed_amount(cents)
    "#{cents.negative? ? '−' : ''}#{format_amount(cents.abs)}"
  end
end
