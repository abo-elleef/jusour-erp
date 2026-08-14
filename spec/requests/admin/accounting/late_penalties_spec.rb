# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Accounting::LatePenalties", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { Current.company }
  let(:owner)   { create(:user, :owner, company: company) }
  let(:manager) { create(:user, :manager, company: company) }
  let(:staff)   { create(:user, name: "Ahmed", company: company, monthly_salary_cents: 300_000) }
  let(:other_staff) { create(:user, name: "Mona", company: company, monthly_salary_cents: 300_000) }

  def create_late!(user, date:, unit: "quarter_day", notes: I18n.t("accounting.attendance.late_note"))
    PayrollAdjustment.create!(
      user: user,
      recorded_by: owner,
      kind: "penalty",
      unit_type: unit,
      payroll_month: date.beginning_of_month,
      happened_at: date,
      notes: notes
    )
  end

  before { sign_in owner }

  describe "GET index" do
    it "groups late penalties by staff and hides staff-page adjustments" do
      create_late!(staff, date: Date.new(2026, 4, 3), unit: "quarter_day")
      create_late!(staff, date: Date.new(2026, 4, 10), unit: "half_day")
      create_late!(other_staff, date: Date.new(2026, 4, 5), unit: "full_day")
      PayrollAdjustment.create!(
        user: staff,
        recorded_by: owner,
        kind: "penalty",
        unit_type: "full_day",
        payroll_month: Date.new(2026, 4, 1),
        happened_at: Date.new(2026, 4, 12),
        notes: "Uniform fine"
      )

      get admin_accounting_late_penalties_path(payroll_month: "2026-04")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(staff.name)
      expect(response.body).to include(other_staff.name)
      expect(response.body).to include(I18n.t("staff.payroll.unit_types.quarter_day"))
      expect(response.body).to include(I18n.t("staff.payroll.unit_types.half_day"))
      expect(response.body).to include(I18n.t("staff.payroll.unit_types.full_day"))
      expect(response.body).not_to include("Uniform fine")
    end

    it "is available to managers" do
      create_late!(staff, date: Date.new(2026, 4, 3))
      sign_in manager

      get admin_accounting_late_penalties_path(payroll_month: "2026-04")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(staff.name)
    end
  end

  describe "DELETE destroy" do
    it "removes the late penalty and returns to the review page" do
      adj = create_late!(staff, date: Date.new(2026, 4, 3), unit: "half_day")

      expect do
        delete admin_accounting_late_penalty_path(adj, payroll_month: "2026-04")
      end.to change(PayrollAdjustment, :count).by(-1)

      expect(response).to redirect_to(admin_accounting_late_penalties_path(payroll_month: "2026-04"))
    end

    it "does not remove a staff-page penalty" do
      adj = PayrollAdjustment.create!(
        user: staff,
        recorded_by: owner,
        kind: "penalty",
        unit_type: "half_day",
        payroll_month: Date.new(2026, 4, 1),
        happened_at: Date.new(2026, 4, 3),
        notes: "Staff page"
      )

      expect do
        delete admin_accounting_late_penalty_path(adj, payroll_month: "2026-04")
      end.not_to change(PayrollAdjustment, :count)
    end
  end
end
