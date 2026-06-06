# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Locale switching", type: :request do
  it "does not require sign-in" do
    patch locale_path, params: { locale: "ar" }, headers: { "HTTP_REFERER" => root_url }

    expect(response).to redirect_to(root_url)
    expect(session[:locale]).to eq("ar")
  end

  it "returns to the staff payroll page when referer is set" do
    staff = User.create!(
      name: "Portal Staff",
      email: "locale-portal@example.com",
      role: "cashier",
      password: "password123",
      monthly_salary_cents: 300_000,
      pin: "1234"
    )

    payroll_url = staff_payroll_url(token: staff.payroll_access_token)

    patch locale_path, params: { locale: "ar" }, headers: { "HTTP_REFERER" => payroll_url }

    expect(response).to redirect_to(payroll_url)
  end
end
