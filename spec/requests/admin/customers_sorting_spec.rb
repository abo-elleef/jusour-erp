# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin customers index sorting", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let(:owner) { create(:user, :owner, company: company) }

  before do
    Current.company = company
    sign_in owner
  end

  it "sorts customers by name ascending" do
    create(:customer, company: company, name: "Zara", email: nil, phone: "01011111111")
    create(:customer, company: company, name: "Adam", email: nil, phone: "01022222222")

    get admin_customers_path, params: { sort: "name", dir: "asc" }

    expect(response).to have_http_status(:ok)
    expect(response.body.index("Adam")).to be < response.body.index("Zara")
  end

  it "sorts customers by lifetime spend descending" do
    create(:customer, company: company, name: "Low Spend", email: nil, phone: "01033333333",
           total_spent_cents: 100_00)
    create(:customer, company: company, name: "High Spend", email: nil, phone: "01044444444",
           total_spent_cents: 900_00)

    get admin_customers_path, params: { sort: "total_spent_cents", dir: "desc" }

    expect(response).to have_http_status(:ok)
    expect(response.body.index("High Spend")).to be < response.body.index("Low Spend")
  end
end
