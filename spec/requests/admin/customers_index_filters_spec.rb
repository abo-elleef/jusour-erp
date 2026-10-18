# frozen_string_literal: true

require "rails_helper"
require "csv"

RSpec.describe "Admin customers index filters and export", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let(:owner) { create(:user, :owner, company: company) }

  before do
    Current.company = company
    sign_in owner
  end

  it "finds a customer by legacy code" do
    create(:customer, company: company, name: "Old Timer", email: nil, phone: "01011111111", legacy_code: "C-9001")
    create(:customer, company: company, name: "Newcomer", email: nil, phone: "01022222222")

    get admin_customers_path, params: { q: { name_or_email_or_phone_or_phone_secondary_or_legacy_code_cont: "9001" } }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Old Timer", "C-9001")
    expect(response.body).not_to include("Newcomer")
  end

  it "shows the legacy code on the customer page" do
    customer = create(:customer, company: company, name: "Old Timer", email: nil, phone: "01011111111",
                      legacy_code: "C-9001")

    get admin_customer_path(customer)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("C-9001")
  end

  it "filters by joined date, inclusive of both ends" do
    create(:customer, company: company, name: "Before Range", email: nil, phone: "01011111111",
           created_at: Time.zone.local(2026, 8, 31, 23, 0))
    create(:customer, company: company, name: "First Day", email: nil, phone: "01022222222",
           created_at: Time.zone.local(2026, 9, 1, 0, 30))
    create(:customer, company: company, name: "Last Day", email: nil, phone: "01033333333",
           created_at: Time.zone.local(2026, 9, 30, 23, 30))

    get admin_customers_path, params: { joined_from: "2026-09-01", joined_to: "2026-09-30" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("First Day", "Last Day")
    expect(response.body).not_to include("Before Range")
  end

  it "ignores an invalid date instead of erroring" do
    get admin_customers_path, params: { joined_from: "not-a-date" }

    expect(response).to have_http_status(:ok)
  end

  it "exports the filtered customers as CSV, not just one page" do
    create(:customer, company: company, name: "In Range", email: nil, phone: "01011111111",
           legacy_code: "L-1", created_at: Time.zone.local(2026, 9, 10))
    create(:customer, company: company, name: "Out Of Range", email: nil, phone: "01022222222",
           created_at: Time.zone.local(2026, 7, 10))

    get admin_customers_path(format: :csv), params: { joined_from: "2026-09-01" }

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/csv")
    rows = CSV.parse(response.body)
    expect(rows.size).to eq(2)
    expect(rows.last).to include("L-1", "In Range", "01011111111")
  end
end
