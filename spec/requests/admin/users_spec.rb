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
