# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Accounting::Attendance", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveSupport::Testing::TimeHelpers

  let(:company) { Current.company }
  let(:owner)   { create(:user, :owner, company: company) }
  let(:staff)   { create(:user, company: company, monthly_salary_cents: 300_000) }

  before { sign_in owner }

  describe "GET index" do
    it "renders the grid listing salaried staff" do
      staff
      get admin_accounting_attendance_path(payroll_month: "2026-04")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(staff.name)
    end

    it "links each staff name to their profile for the same payroll month" do
      staff
      get admin_accounting_attendance_path(payroll_month: "2026-04")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(admin_user_path(staff, payroll_month: "2026-04"))
    end

    it "defaults to the previous month through the 5th of the new month" do
      travel_to Date.new(2026, 8, 1) do
        get admin_accounting_attendance_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include('value="2026-07"')
      end
    end

    it "defaults to the current month from the 6th onward" do
      travel_to Date.new(2026, 8, 6) do
        get admin_accounting_attendance_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include('value="2026-08"')
      end
    end
  end

  describe "PATCH update" do
    it "upserts a cell and returns the recomputed summary" do
      patch admin_accounting_attendance_path,
        params: { cells: [{ user_id: staff.id, date: "2026-04-01", symbol: "P" }] }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["ok"]).to be(true)
      expect(StaffAttendance.where(user: staff, date: Date.new(2026, 4, 1)).count).to eq(1)
      expect(response.parsed_body["summaries"][staff.id]["payable"]).to eq("1")
    end

    it "clears the cell when the symbol is blank" do
      status = company.attendance_statuses.find_by!(code: "present")
      StaffAttendance.create!(company: company, user: staff, attendance_status: status,
                              date: Date.new(2026, 4, 1), recorded_by: owner)

      patch admin_accounting_attendance_path,
        params: { cells: [{ user_id: staff.id, date: "2026-04-01", symbol: "" }] }, as: :json

      expect(response).to have_http_status(:ok)
      expect(StaffAttendance.where(user: staff).count).to eq(0)
    end

    it "ignores a user that belongs to another company" do
      other = create(:user, company: create(:company), monthly_salary_cents: 300_000)

      patch admin_accounting_attendance_path,
        params: { cells: [{ user_id: other.id, date: "2026-04-01", symbol: "P" }] }, as: :json

      expect(response).to have_http_status(:ok)
      expect(StaffAttendance.unscoped.where(user_id: other.id).count).to eq(0)
    end
  end

  describe "POST adjustment" do
    let(:date) { "2026-04-03" }

    it "records a late penalty with a Late note and returns the unit" do
      post admin_accounting_attendance_adjustment_path,
        params: { user_id: staff.id, date: date, overtime_hours: "", penalty: "quarter_day" }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["ok"]).to be(true)
      expect(response.parsed_body["penalty_unit"]).to eq("quarter_day")

      adj = staff.payroll_adjustments.find_by!(kind: "penalty", happened_at: Date.new(2026, 4, 3))
      expect(adj.unit_type).to eq("quarter_day")
      expect(adj.notes).to eq(I18n.t("accounting.attendance.late_note"))
    end

    it "records overtime with an Overtime note" do
      post admin_accounting_attendance_adjustment_path,
        params: { user_id: staff.id, date: date, overtime_hours: "2", penalty: "" }, as: :json

      expect(response).to have_http_status(:ok)
      adj = staff.payroll_adjustments.find_by!(kind: "bonus", unit_type: "overtime", happened_at: Date.new(2026, 4, 3))
      expect(adj.overtime_hours).to eq(2)
      expect(adj.notes).to eq(I18n.t("accounting.attendance.overtime_note"))
    end

    it "does not show a staff-page penalty on the attendance grid" do
      PayrollAdjustment.create!(
        user: staff,
        recorded_by: owner,
        kind: "penalty",
        unit_type: "half_day",
        payroll_month: Date.new(2026, 4, 1),
        happened_at: Date.new(2026, 4, 3),
        notes: "Manager deduction"
      )

      get admin_accounting_attendance_path(payroll_month: "2026-04")

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('data-penalty-unit="half_day"')
    end

    it "shows an attendance late penalty on the grid and keeps the staff-page one" do
      staff_page = PayrollAdjustment.create!(
        user: staff,
        recorded_by: owner,
        kind: "penalty",
        unit_type: "full_day",
        payroll_month: Date.new(2026, 4, 1),
        happened_at: Date.new(2026, 4, 3),
        notes: "Uniform fine"
      )

      post admin_accounting_attendance_adjustment_path,
        params: { user_id: staff.id, date: date, overtime_hours: "", penalty: "quarter_day" }, as: :json

      expect(response.parsed_body["penalty_unit"]).to eq("quarter_day")
      expect(staff.payroll_adjustments.reload.count).to eq(2)
      expect(staff_page.reload.unit_type).to eq("full_day")
      expect(staff_page.notes).to eq("Uniform fine")

      get admin_accounting_attendance_path(payroll_month: "2026-04")
      expect(response.body).to include('data-penalty-unit="quarter_day"')
      expect(response.body).not_to include('data-penalty-unit="full_day"')
    end

    it "clears only the attendance late penalty, leaving a staff-page penalty" do
      PayrollAdjustment.create!(
        user: staff,
        recorded_by: owner,
        kind: "penalty",
        unit_type: "full_day",
        payroll_month: Date.new(2026, 4, 1),
        happened_at: Date.new(2026, 4, 3),
        notes: "Staff page"
      )
      PayrollAdjustment.create!(
        user: staff,
        recorded_by: owner,
        kind: "penalty",
        unit_type: "half_day",
        payroll_month: Date.new(2026, 4, 1),
        happened_at: Date.new(2026, 4, 3),
        notes: I18n.t("accounting.attendance.late_note")
      )

      post admin_accounting_attendance_adjustment_path,
        params: { user_id: staff.id, date: date, overtime_hours: "", penalty: "" }, as: :json

      remaining = staff.payroll_adjustments.reload
      expect(remaining.count).to eq(1)
      expect(remaining.first.notes).to eq("Staff page")
      expect(response.parsed_body["penalty_unit"]).to be_nil
    end
  end
end
