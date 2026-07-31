# frozen_string_literal: true

module Accounting
  class ClockOutService
    class Error < StandardError; end

    def initialize(shift_log, user:)
      @shift = shift_log
      @user = user
    end

    def call
      raise Error, "Shift is not active" unless @shift.status == "active"

      @shift.update!(clocked_out_at: Time.current, status: "completed")

      tips = Payment.joins(:order)
        .where(orders: { user_id: @shift.user_id })
        .where(status: "completed")
        .where(created_at: @shift.clocked_in_at..@shift.clocked_out_at)
        .sum(:tip_cents).to_i
      @shift.update!(tips_cents: tips)

      checker = OvertimeCheckService.new(@shift.user)
      if checker.over_overtime?
        NotifyService.deliver_to_managers(
          message_key: "overtime_shift",
          message_params: { name: @shift.user.name }
        )
      end

      AuditLogEntry.record!(action: "shift.clock_out", record: @shift, user: @user)
      @shift
    end
  end
end
