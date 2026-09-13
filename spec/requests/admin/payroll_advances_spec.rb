# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin payroll advances", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveSupport::Testing::TimeHelpers

  let(:company) { create(:company) }
  let(:owner) { create(:user, :owner, company: company) }
  let(:staff) do
    create(:user, company: company, role: "cashier", monthly_salary_cents: 300_000)
  end
  let(:treasury) do
    Treasury.create!(
      company: company,
      name: "Main Safe",
      treasury_type: "safe",
      opening_balance_cents: 500_000,
      balance_cents: 500_000
    )
  end
  let(:payroll_month) { Date.new(2026, 6, 1) }

  before do
    Current.company = company
    sign_in owner
  end

  describe "POST /admin/users/:user_id/payroll_advances" do
    it "pays an advance dated within the month" do
      expect do
        post admin_user_payroll_advances_path(staff), params: {
          payroll_advance: {
            paid_on: "2026-06-10",
            amount_pounds: 1000.00,
            treasury_id: treasury.id
          }
        }
      end.to change(PayrollAdvance, :count).by(1)

      expect(response).to redirect_to(admin_user_path(staff, payroll_month: payroll_month.strftime("%Y-%m")))

      advance = PayrollAdvance.last
      expect(advance).to have_attributes(amount_cents: 100_000, payroll_month: payroll_month, paid_on: Date.new(2026, 6, 10))
      expect(treasury.reload.balance_cents).to eq(400_000)

      summary = Accounting::MonthlyPayrollService.new(staff, payroll_month).call
      expect(summary.advances_cents).to eq(100_000)
      expect(summary.remaining_pay_cents).to eq(200_000)
    end

    it "rejects advances after payroll is recorded" do
      travel_to Time.zone.local(2026, 6, 15, 10, 0, 0) do
        Accounting::FinalizePayrollService.new(
          staff,
          payroll_month,
          finalized_by: owner,
          treasury: treasury,
          paid_on: payroll_month.end_of_month
        ).call

        expect do
          post admin_user_payroll_advances_path(staff), params: {
            payroll_advance: {
              paid_on: "2026-06-15",
              amount_pounds: 500.00,
              treasury_id: treasury.id
            }
          }
        end.not_to change(PayrollAdvance, :count)

        expect(response).to redirect_to(admin_user_path(staff, payroll_month: payroll_month.strftime("%Y-%m")))
      end
    end
  end

  describe "DELETE /admin/users/:user_id/payroll_advances/:id" do
    it "removes an advance and restores treasury balance" do
      travel_to Time.zone.local(2026, 6, 15, 10, 0, 0) do
        advance = Accounting::PayPayrollAdvanceService.new(
          user: staff,
          amount_cents: 100_000,
          treasury: treasury,
          paid_by: owner,
          paid_on: Date.new(2026, 6, 15)
        ).call

        expect do
          delete admin_user_payroll_advance_path(staff, advance)
        end.to change(PayrollAdvance, :count).by(-1)

        expect(treasury.reload.balance_cents).to eq(500_000)
      end
    end

    # The treasury side was always cleaned up; the journal side was not, so the
    # advance vanished while its entry stayed on the books and the P&L kept
    # reporting salary advances that had been deleted.
    it "removes the advance's journal entry too" do
      travel_to Time.zone.local(2026, 6, 15, 10, 0, 0) do
        advance = Accounting::PayPayrollAdvanceService.new(
          user: staff,
          amount_cents: 100_000,
          treasury: treasury,
          paid_by: owner,
          paid_on: Date.new(2026, 6, 15)
        ).call

        expect(JournalEntry.where(source_record: advance)).to exist

        delete admin_user_payroll_advance_path(staff, advance)

        expect(JournalEntry.where(source_record_type: "PayrollAdvance",
                                  source_record_id: advance.id)).to be_empty
        expect(TreasuryTransaction.where(source_record_type: "PayrollAdvance",
                                         source_record_id: advance.id)).to be_empty
      end
    end
  end
end
