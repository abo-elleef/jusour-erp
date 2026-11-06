# frozen_string_literal: true

module Accounting
  # Staff who owe the company money: an employee account (User#wages_account_code)
  # in credit-normal terms is negative, meaning they were paid ahead of what
  # they earned. Payroll pays the full salary and ignores this; the accountant
  # collects repayments with a receipt voucher, and this report is where they
  # see who owes what.
  #
  # Reads the balance the same way User#staff_balance_cents does, but for every
  # employee in one grouped query. Someone who has since left still shows while
  # they owe.
  class StaffDebtsReportService
    SORTABLE_COLUMNS = %w[name owed_cents plan_cents repaid_cents due_cents last_repaid_on].freeze
    DEFAULT_SORT = "owed_cents"

    Row = Struct.new(:user, :owed_cents, :plan_cents, :repaid_cents, :due_cents, :last_repaid_on, keyword_init: true)

    attr_reader :month

    def initialize(month, users:, sort: nil, direction: nil)
      @month = month.to_date.beginning_of_month
      @users = users
      @sort = SORTABLE_COLUMNS.include?(sort.to_s) ? sort.to_s : DEFAULT_SORT
      @direction = direction.to_s.presence_in(%w[asc desc]) || (@sort == "name" ? "asc" : "desc")
    end

    def rows
      @rows ||= begin
        built = debtors.map { |user| build_row(user) }
        sorted = built.sort_by { |row| sort_key(row) }
        @direction == "desc" ? sorted.reverse : sorted
      end
    end

    def total(column) = rows.sum { |row| row.public_send(column).to_i }

    private

    def sort_key(row)
      case @sort
      when "name" then row.user.name.downcase
      when "last_repaid_on" then row.last_repaid_on || Date.new(1900, 1, 1)
      else row.public_send(@sort).to_i
      end
    end

    def build_row(user)
      owed = -balances.fetch(user.wages_account_code)
      plan = user.balance_deduction_cents
      repaid = repaid_this_month[user.id].to_i
      Row.new(
        user: user,
        owed_cents: owed,
        plan_cents: plan,
        repaid_cents: repaid,
        # Nothing is "due" without a plan: the accountant collects what they
        # agree with the employee.
        due_cents: plan ? [[plan, owed].min - repaid, 0].max : nil,
        last_repaid_on: last_repayment[user.id]
      )
    end

    # Employees whose account is negative, with the amount in cents.
    def debtors
      @debtors ||= candidates.select { |user| balances.key?(user.wages_account_code) }
    end

    def candidates
      @candidates ||= @users.where.not(wages_account_code: nil).order(:name).to_a
    end

    # { account_code => balance_cents } for negative balances only.
    def balances
      @balances ||= begin
        company_ids = candidates.map(&:company_id).uniq
        JournalEntryLine.joins(:journal_entry)
                        .where(journal_entries: { company_id: company_ids })
                        .where(account_code: candidates.map(&:wages_account_code))
                        .group(:account_code)
                        .sum("journal_entry_lines.credit_cents - journal_entry_lines.debit_cents")
                        .select { |_code, balance| balance.negative? }
      end
    end

    # Receipt vouchers from staff dated in the month. Voided ones are excluded
    # explicitly, not trusted to a scope name.
    def repaid_this_month
      @repaid_this_month ||= staff_receipts.where(voucher_date: @month..@month.end_of_month)
                                           .group(:party_id).sum(:amount_cents)
    end

    def last_repayment
      @last_repayment ||= staff_receipts.group(:party_id).maximum(:voucher_date)
    end

    def staff_receipts
      Voucher.where(voided_at: nil, direction: Voucher::RECEIPT, party_type: "User",
                    party_id: debtors.map(&:id))
    end
  end
end
