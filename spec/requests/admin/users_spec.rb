# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Users", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let(:owner) { create(:user, :owner, company: company) }
  let(:manager) { create(:user, :manager, company: company) }

  before { Current.company = company }

  describe "as owner" do
    before { sign_in owner }

    describe "GET /admin/users" do
      it "lists staff members" do
        staff = create(:user, company: company, name: "Alice Cashier")

        get admin_users_path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(staff.name)
        expect(response.body).to include(I18n.t("staff.index.new_button"))
      end

      it "shows inactive staff and their status" do
        inactive = create(:user, company: company, name: "Former Staff", active: false)

        get admin_users_path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(inactive.name)
        expect(response.body).to include(I18n.t("staff.show.inactive"))
      end

      it "filters by active status" do
        active_staff = create(:user, company: company, name: "Active Staff")
        create(:user, company: company, name: "Inactive Staff", active: false)

        get admin_users_path, params: { q: { active_eq: true } }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(active_staff.name)
        expect(response.body).not_to include("Inactive Staff")
      end

      it "filters staff by location" do
        downtown = create(:location, company: company, name: "Downtown")
        uptown = create(:location, company: company, name: "Uptown")
        branch_staff = create(:user, company: company, name: "Branch Cashier", all_locations: false)
        branch_staff.locations = [downtown]
        other_staff = create(:user, company: company, name: "Other Branch", all_locations: false)
        other_staff.locations = [uptown]
        create(:user, company: company, name: "Company Wide", all_locations: true)

        get admin_users_path, params: { location_id: downtown.id }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Branch Cashier")
        expect(response.body).not_to include("Other Branch")
        expect(response.body).not_to include("Company Wide")
      end

      it "filters to company-wide staff only" do
        downtown = create(:location, company: company, name: "Downtown")
        create(:location, company: company, name: "Uptown")
        branch_staff = create(:user, company: company, name: "Branch Cashier", all_locations: false)
        branch_staff.locations = [downtown]
        create(:user, company: company, name: "Company Wide", all_locations: true)

        get admin_users_path, params: { location_id: StaffLocationFilter::COMPANY_WIDE_FILTER }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Company Wide")
        expect(response.body).not_to include("Branch Cashier")
      end

      it "sorts staff by name descending" do
        create(:user, company: company, name: "Zara Staff")
        create(:user, company: company, name: "Adam Staff")

        get admin_users_path, params: { sort: "name", direction: "desc" }

        expect(response).to have_http_status(:ok)
        expect(response.body.index("Zara Staff")).to be < response.body.index("Adam Staff")
      end

      it "sorts staff by monthly salary ascending" do
        create(:user, company: company, name: "Higher Paid", monthly_salary_cents: 400_000)
        create(:user, company: company, name: "Lower Paid", monthly_salary_cents: 100_000)

        get admin_users_path, params: { sort: "monthly_salary_cents", direction: "asc" }

        expect(response).to have_http_status(:ok)
        expect(response.body.index("Lower Paid")).to be < response.body.index("Higher Paid")
      end
    end

    describe "POST /admin/users" do
      it "creates a staff member" do
        expect do
          post admin_users_path, params: {
            user: {
              name: "New Cashier",
              email: "new-cashier@example.com",
              role: "cashier",
              password: "password123",
              password_confirmation: "password123",
              monthly_salary_pounds: 2500.00,
              pin: "4321"
            }
          }
        end.to change(User, :count).by(1)

        created = User.find_by!(email: "new-cashier@example.com")
        expect(created).to have_attributes(name: "New Cashier", role: "cashier", monthly_salary_cents: 250_000)
        expect(created.authenticate_pin("4321")).to be(true)
        expect(response).to redirect_to(admin_user_path(created))
        follow_redirect!
        expect(response.body).to include("New Cashier")
      end
    end

    describe "PATCH /admin/users/:id" do
      it "updates a staff member" do
        staff = create(:user, company: company, name: "Before Edit")

        patch admin_user_path(staff), params: {
          user: { name: "After Edit", monthly_salary_pounds: 3000.00 }
        }

        expect(response).to redirect_to(admin_user_path(staff))
        expect(staff.reload).to have_attributes(name: "After Edit", monthly_salary_cents: 300_000)
      end
    end

    describe "GET /admin/users/:id payroll month default" do
      include ActiveSupport::Testing::TimeHelpers

      it "defaults the payroll section to the previous month through the 5th" do
        staff = create(:user, company: company, monthly_salary_cents: 300_000)

        travel_to Date.new(2026, 8, 1) do
          get admin_user_path(staff)
          expect(response).to have_http_status(:ok)
          expect(response.body).to include('value="2026-07"')
        end
      end
    end

    describe "GET /admin/users/:id attendance history" do
      it "shows every change to this staff member's attendance for the month" do
        staff = create(:user, company: company, monthly_salary_cents: 300_000)
        status = company.attendance_statuses.find_by!(code: "present")
        record = StaffAttendance.create!(company: company, user: staff, attendance_status: status,
          date: Date.new(2026, 4, 1), recorded_by: owner)
        AuditLogEntry.record!(action: "create", record: record, user: owner,
          changes_snapshot: { "attendance_status_id" => [nil, status.id] })

        get admin_user_path(staff, payroll_month: "2026-04")

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(I18n.t("accounting.attendance.staff_history_title"))
        expect(response.body).to include(status.label)
      end
    end

    describe "GET /admin/users/:id payroll account ledger" do
      it "shows the balance and links a voucher-sourced row to the voucher" do
        staff = create(:user, company: company, role: "cashier", monthly_salary_cents: 300_000)
        treasury = Treasury.create!(company: company, name: "Safe", treasury_type: "safe",
                                    opening_balance_cents: 100_000, balance_cents: 100_000)
        voucher = Accounting::RecordVoucherService.new(
          direction: Voucher::PAYMENT, treasury: treasury, user: owner, amount_cents: 20_000,
          party_type: "User", party_id: staff.id
        ).call

        get admin_user_path(staff)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(I18n.t("staff.wages_ledger.title"))
        expect(response.body).to include(admin_accounting_voucher_path(voucher))
      end

      it "shows no movements for a staff member with no payroll activity" do
        staff = create(:user, company: company, role: "cashier")

        get admin_user_path(staff)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(I18n.t("staff.wages_ledger.no_movements"))
      end
    end

    describe "DELETE /admin/users/:id" do
      it "deactivates a staff member" do
        staff = create(:user, company: company)

        expect do
          delete admin_user_path(staff)
        end.not_to change(User, :count)

        expect(response).to redirect_to(admin_users_path)
        expect(staff.reload.active?).to be(false)
      end
    end
  end

  describe "as manager" do
    before { sign_in manager }

    it "cannot access the staff index" do
      get admin_users_path

      expect(response).not_to have_http_status(:ok)
    end
  end
end
