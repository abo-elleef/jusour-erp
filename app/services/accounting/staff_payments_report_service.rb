# frozen_string_literal: true

module Accounting
  # Money to staff for one month, per employee: what their pay is, what they
  # earned in the month, what actually went to them (payment vouchers) and
  # came back (receipt vouchers), and where their account stands now.
  #
  # Earned comes from MonthlyPayrollService, so it is the finalized figure
  # when the month is finalized and the live estimate when it isn't.
  class StaffPaymentsReportService
    SORTABLE_COLUMNS = %w[name monthly_salary_cents earned_cents paid_out_cents received_cents
                          net_paid_cents staff_meals_cents balance_cents].freeze
    DEFAULT_SORT = "name"

    Row = Struct.new(:user, :monthly_salary_cents, :earned_cents, :finalized, :paid_out_cents,
                     :received_cents, :staff_meals_cents, :balance_cents, keyword_init: true) do
      def net_paid_cents = paid_out_cents - received_cents
    end

    attr_reader :month

    def initialize(month, users:, sort: nil, direction: nil)
      @month = month.to_date.beginning_of_month
      @users = users
      @sort = SORTABLE_COLUMNS.include?(sort.to_s) ? sort.to_s : DEFAULT_SORT
      @direction = direction.to_s == "desc" ? :desc : :asc
    end

    def rows
      @rows ||= begin
        built = report_users.map { |user| build_row(user) }
        sorted = @sort == "name" ? built.sort_by { |r| r.user.name.downcase } : built.sort_by { |r| r.public_send(@sort).to_i }
        @direction == :desc ? sorted.reverse : sorted
      end
    end

    # Every voucher to or from staff in the month, newest first — the detail
    # behind the paid / received columns.
    def vouchers
      @vouchers ||= month_vouchers.where(party_id: report_users.map(&:id))
                                  .includes(:treasury, :party)
                                  .order(voucher_date: :desc, created_at: :desc)
    end

    def total(column) = rows.sum { |r| r.public_send(column).to_i }

    private

    def build_row(user)
      summary = MonthlyPayrollService.new(user, @month).call
      Row.new(
        user: user,
        monthly_salary_cents: user.monthly_salary_cents.to_i,
        earned_cents: [summary.net_pay_cents, 0].max,
        finalized: summary.finalized,
        paid_out_cents: voucher_totals[[user.id, Voucher::PAYMENT]].to_i,
        received_cents: voucher_totals[[user.id, Voucher::RECEIPT]].to_i,
        staff_meals_cents: summary.staff_meals_cents,
        balance_cents: summary.balance_cents
      )
    end

    # Anyone on payroll this month, plus anyone money went to or came from —
    # an employee without a salary can still be paid, and someone who has
    # since left still shows for a month they were paid or finalized in.
    def report_users
      @report_users ||= begin
        paid_ids = month_vouchers.distinct.pluck(:party_id).to_set
        @users.order(:name).select do |user|
          next true if paid_ids.include?(user.id) || snapshots.key?(user.id)

          user.active? && MonthlyPayrollService.payroll_row?(user, @month, nil)
        end
      end
    end

    def snapshots
      @snapshots ||= PayrollSnapshot.for_month(@month).index_by(&:user_id)
    end

    def voucher_totals
      @voucher_totals ||= month_vouchers.group(:party_id, :direction).sum(:amount_cents)
    end

    def month_vouchers
      Voucher.active.where(party_type: "User", voucher_date: @month..@month.end_of_month)
    end
  end
end
