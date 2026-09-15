# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Account::Passwords", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }

  before { Current.company = company }

  describe "GET /account/password/edit" do
    it "is reachable by a cashier, who cannot open the staff admin pages" do
      sign_in create(:user, company: company, role: "cashier")

      get edit_account_password_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("auth.change_password_title"))
    end

    it "is reachable by kitchen staff" do
      sign_in create(:user, company: company, role: "kitchen")

      get edit_account_password_path

      expect(response).to have_http_status(:ok)
    end

    it "redirects a signed-out visitor to sign in" do
      get edit_account_password_path

      expect(response).to redirect_to(new_user_session_path)
    end
  end

  describe "PATCH /account/password" do
    let(:user) { create(:user, company: company, role: "cashier", password: "password123") }

    before { sign_in user }

    it "changes the password and keeps the user signed in" do
      patch account_password_path, params: {
        user: {
          current_password: "password123",
          password: "newpassword1",
          password_confirmation: "newpassword1"
        }
      }

      expect(response).to redirect_to(pos_path)
      expect(user.reload.valid_password?("newpassword1")).to be(true)

      follow_redirect!
      expect(response).to have_http_status(:ok)
    end

    it "rejects a wrong current password" do
      patch account_password_path, params: {
        user: {
          current_password: "wrongpassword",
          password: "newpassword1",
          password_confirmation: "newpassword1"
        }
      }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(user.reload.valid_password?("password123")).to be(true)
    end

    it "rejects a mismatched confirmation" do
      patch account_password_path, params: {
        user: {
          current_password: "password123",
          password: "newpassword1",
          password_confirmation: "differentpass"
        }
      }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(user.reload.valid_password?("password123")).to be(true)
    end

    it "rejects a blank new password instead of silently succeeding" do
      patch account_password_path, params: {
        user: { current_password: "password123", password: "", password_confirmation: "" }
      }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(user.reload.valid_password?("password123")).to be(true)
    end

    it "rejects a new password shorter than the model minimum" do
      patch account_password_path, params: {
        user: { current_password: "password123", password: "abc12", password_confirmation: "abc12" }
      }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(user.reload.valid_password?("password123")).to be(true)
    end
  end
end
