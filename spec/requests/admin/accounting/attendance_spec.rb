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
end
