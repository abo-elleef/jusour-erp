# frozen_string_literal: true

module Accounting
  class MonthlyPayrollService
    INDEX_SORTABLE_COLUMNS = %w[
      name base_salary_cents attendance_pay_cents daily_rate_cents penalties_cents bonuses_cents
      net_pay_cents paid_cents staff_meals_cents payout_cents status
    ].freeze
    INDEX_DEFAULT_SORT = "name"
    INDEX_DEFAULT_SORT_DIRECTION = "asc"

    Result = Struct.new(
      :user,
      :payroll_month,
      :base_salary_cents,
      :attendance_pay_cents,
      :attendance_recorded,
      :payable_days,
      :bonus_days,
      :penalty_days,
      :daily_rate_cents,
      :penalties_cents,
      :penalties_waived_cents,
      :bonuses_cents,
      :net_pay_cents,
      :paid_cents,
      :staff_meals_cents,
      :balance_cents,
      :remaining_pay_cents,
      :debt_cents,
      :deduction_cents,
      :payout_cents,
      :adjustments,
      :payments,
      :finalized,
      :snapshot,
      keyword_init: true
    ) do
      # What the company still has to hand over to this employee for the
      # month, as salary: the payout while it is unpaid, otherwise whatever
      # positive balance is left. The debt side of the account is on the
      # Staff debts report, not here.
      def still_to_pay_cents
        return [payout_cents.to_i, 0].max unless finalized && snapshot&.paid_out?

        [remaining_pay_cents.to_i, 0].max
      end

      # What they owe the company once this month's pay has gone out. The
      # ledger balance, adjusted for a payout that hasn't been made yet.
      def debt_after_cents
        after = if finalized
                  balance_cents.to_i - (snapshot&.paid_out? ? 0 : payout_cents.to_i)
                else
                  balance_cents.to_i + [net_pay_cents.to_i, 0].max - payout_cents.to_i
                end
        [-after, 0].max
      end
    end

    Payout = Struct.new(:debt_cents, :max_deduction_cents, :deduction_cents, :payout_cents, keyword_init: true)

    # What finalizing a month pays out, given where the account stood before
    # the month's earnings were credited (balance_before: + owed to them,
    # − they owe the company) and what was already paid to them or eaten
    # during the month (month_payments: vouchers and staff meals).
    #
    # Money they owed the company before the month began is not touched: it is
    # repaid separately, by a receipt voucher (Staff debts report), after they
    # have their full salary. Only the month's own payments come off the pay:
    #
    #   opening = balance_before + month_payments
    #   payout  = max(max(opening, 0) + net_pay − month_payments, 0)
    #
    # If the month's payments exceed what they were owed, the excess stays on
    # their account as a debt.
    def self.payout_for(balance_before_cents:, net_pay_cents:, month_payments_cents: 0)
      net = [net_pay_cents.to_i, 0].max
      payments = month_payments_cents.to_i
      opening = balance_before_cents.to_i + payments

      Payout.new(debt_cents: [-balance_before_cents.to_i, 0].max, max_deduction_cents: 0, deduction_cents: 0,
                 payout_cents: [[opening, 0].max + net - payments, 0].max)
    end

    # Penalties come out of what the month leaves after its own payments —
    # advances and staff meals — and never push the account below zero. The
    # rest is waived: a month already spent in advance isn't turned into debt
    # by penalties. Only this month's payments count, so someone repaying an
    # old advance over several months is still penalized as normal.
    #
    #   applied = min(penalties, max(attendance + bonuses − month's payments, 0))
    def self.penalties_waived_for(penalties_cents:, earned_cents:, month_payments_cents:)
      room = [earned_cents.to_i - month_payments_cents.to_i, 0].max
      [penalties_cents.to_i - room, 0].max
    end

    def initialize(user, payroll_month, sort: nil, direction: nil, waive_penalties: true)
      @waive_penalties = waive_penalties
      @user = user
      @payroll_month = payroll_month.to_date.beginning_of_month
      @sort = PayrollAdjustment::SORTABLE_COLUMNS.include?(sort.to_s) ? sort.to_s : PayrollAdjustment::DEFAULT_SORT
      @direction = direction.to_s == "asc" ? :asc : :desc
    end

    def call
      built = build_calculated
      snapshot = PayrollSnapshot.find_by(user: @user, payroll_month: @payroll_month)
      return with_snapshot(built, snapshot) if snapshot

      built
    end

    def build_calculated
      adjustments    = sorted_adjustments
      payments       = @user.staff_vouchers_for_month(@payroll_month)
      full_salary    = @user.monthly_salary_cents.to_i

      # Attendance drives base pay for everyone except owners. Owners keep a
      # fixed monthly salary. If a month has nothing recorded, fall back to the
      # full salary so legacy months are unaffected until the grid is used.
      attendance     = AttendanceMonthService.new(@user, @payroll_month).call
      recorded       = @user.attendance_paid? && attendance.marked_days.positive?
      attendance_pay = recorded ? attendance.base_pay_cents : full_salary

      penalties      = adjustments.penalties.sum(:amount_cents)
      bonuses        = adjustments.bonuses.sum(:amount_cents)
      meals_total    = staff_meals_for_month
      paid           = payments.sum(&:signed_amount_cents) * -1
      waived         = if @waive_penalties
                         self.class.penalties_waived_for(penalties_cents: penalties,
                                                         earned_cents: attendance_pay + bonuses,
                                                         month_payments_cents: paid + meals_total)
                       else
                         0
                       end
      gross_net      = attendance_pay - penalties + waived + bonuses
      # As of the month's last day: later months' payments and accruals don't
      # belong to this month's figures — except this month's own salary
      # payout, which counts here even when it went out early next month.
      balance        = @user.staff_month_end_balance_cents(@payroll_month)

      Result.new(
        user: @user,
        payroll_month: @payroll_month,
        base_salary_cents: full_salary,
        attendance_pay_cents: attendance_pay,
        attendance_recorded: recorded,
        payable_days: attendance.payable_days,
        bonus_days: attendance.bonus_days,
        penalty_days: attendance.penalty_days,
        daily_rate_cents: @user.daily_rate_cents,
        penalties_cents: penalties,
        penalties_waived_cents: waived,
        bonuses_cents: bonuses,
        net_pay_cents: gross_net,
        paid_cents: paid,
        staff_meals_cents: meals_total,
        balance_cents: balance,
        # Not finalized yet, so this month's earnings aren't on the account:
        # what they'd be owed once it is. Payments and meals — this month's
        # and any earlier month's still unsettled — are already in the balance.
        # Not floored: penalties beyond the month's pay show as a real negative
        # here, even though finalizing will only ever accrue zero for it.
        remaining_pay_cents: balance + gross_net,
        **payout_fields(self.class.payout_for(balance_before_cents: balance, net_pay_cents: gross_net,
                                              month_payments_cents: paid + meals_total)),
        adjustments: adjustments,
        payments: payments,
        finalized: false,
        snapshot: nil
      )
    end

    def self.for_all_staff(payroll_month, users: User.active)
      snapshots = PayrollSnapshot.for_month(payroll_month).index_by(&:user_id)

      users.order(:name).filter_map do |user|
        next unless payroll_row?(user, payroll_month, snapshots[user.id])

        new(user, payroll_month).call
      end
    end

    def self.payroll_row?(user, payroll_month, snapshot)
      return true if snapshot

      user.monthly_salary_cents.to_i.positive? ||
        user.payroll_adjustments.for_month(payroll_month).exists? ||
        user.staff_vouchers_for_month(payroll_month).exists?
    end

    def self.sort_rows(rows, sort:, direction:)
      sort = INDEX_SORTABLE_COLUMNS.include?(sort.to_s) ? sort.to_s : INDEX_DEFAULT_SORT
      direction = direction.to_s == "desc" ? :desc : :asc

      sorted = case sort
               when "name"
                 rows.sort_by { |row| row.user.name.downcase }
               when "status"
                 rows.sort_by { |row| row.finalized ? 1 : 0 }
               else
                 rows.sort_by { |row| row.public_send(sort).to_i }
               end

      direction == :desc ? sorted.reverse : sorted
    end

    private

    def payout_fields(payout)
      { debt_cents: payout.debt_cents, deduction_cents: payout.deduction_cents, payout_cents: payout.payout_cents }
    end

    def staff_meals_for_month
      month_start = @payroll_month.beginning_of_month.beginning_of_day
      month_end   = @payroll_month.end_of_month.end_of_day

      Payment
        .joins(:order)
        .where(payment_method: "staff_deduction", status: "completed")
        .where(orders: { staff_meal_user_id: @user.id, company_id: @user.company_id })
        .where(created_at: month_start..month_end)
        .sum(:amount_cents)
        .to_i
    end

    def sorted_adjustments
      scope = @user.payroll_adjustments.for_month(@payroll_month).includes(:recorded_by)

      case @sort
      when "recorded_by"
        scope.joins(:recorded_by).order(Arel.sql("users.name #{sql_direction}"))
      when "notes"
        scope.order(Arel.sql("payroll_adjustments.notes #{sql_direction} NULLS LAST"))
      else
        scope.order(@sort => @direction, created_at: :desc)
      end
    end

    def sql_direction
      @direction == :asc ? "ASC" : "DESC"
    end

    def with_snapshot(calculated, snapshot)
      recorded = (snapshot.payable_days.to_d + snapshot.bonus_days.to_d + snapshot.penalty_days.to_d).positive?
      Result.new(
        user: calculated.user,
        payroll_month: calculated.payroll_month,
        base_salary_cents: snapshot.base_salary_cents,
        attendance_pay_cents: recorded ? snapshot.attendance_pay_cents : snapshot.base_salary_cents,
        attendance_recorded: recorded,
        payable_days: snapshot.payable_days,
        bonus_days: snapshot.bonus_days,
        penalty_days: snapshot.penalty_days,
        daily_rate_cents: snapshot.daily_rate_cents,
        penalties_cents: snapshot.penalties_cents,
        penalties_waived_cents: snapshot.penalties_waived_cents,
        bonuses_cents: snapshot.bonuses_cents,
        net_pay_cents: snapshot.net_pay_cents,
        paid_cents: calculated.paid_cents,
        staff_meals_cents: snapshot.staff_meals_cents,
        balance_cents: calculated.balance_cents,
        # Finalized: the month's earnings are on the account, so what's still
        # owed is simply the balance.
        remaining_pay_cents: calculated.balance_cents,
        debt_cents: [-calculated.balance_cents, 0].max,
        deduction_cents: snapshot.deduction_cents,
        # Paid out: what went to them. Recorded to pay later: what's due.
        payout_cents: snapshot.paid_out? ? snapshot.remaining_pay_cents : snapshot.payout_due_cents,
        adjustments: calculated.adjustments,
        payments: calculated.payments,
        finalized: true,
        snapshot: snapshot
      )
    end
  end
end
