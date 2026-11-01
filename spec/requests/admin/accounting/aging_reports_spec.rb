# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Accounting aging reports", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company, business_type: "distribution") }
  let(:owner) { create(:user, :owner, company: company, wages_account_code: 2501) }
  let(:location) { create(:location, company: company) }

  before do
    Current.company = company
    sign_in owner
  end

  it "shows each customer's open balance by age, linked to their statement" do
    customer = create(:customer, company: company, name: "Late Clinic", credit_terms_days: 0)
    invoice = CustomerInvoice.create!(company: company, customer: customer, user: owner,
                                      location: location, invoice_date: 100.days.ago.to_date)
    invoice.update_columns(total_cents: 12_345_00, status: "confirmed", payment_status: "unpaid")

    get receivable_admin_accounting_aging_reports_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("accounting.aging.receivable.title"))
    expect(response.body).to include(admin_sales_customer_statement_path(customer))
    expect(response.body).to include("12,345")
  end

  it "shows each supplier's open balance, linked to the statement tab" do
    supplier = Supplier.create!(name: "Mill", lead_time_days: 1, company: company)

    get payable_admin_accounting_aging_reports_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("accounting.aging.payable.empty"))

    supplier.ap_treasury.update_columns(balance_cents: 500_00)
    get payable_admin_accounting_aging_reports_path
    expect(response.body).to include(admin_inventory_supplier_path(supplier, tab: "statement"))
  end

  it "filters customers to overdue ones with a switch that CSV and print carry along" do
    late = create(:customer, company: company, name: "Late Clinic", credit_terms_days: 0)
    on_time = create(:customer, company: company, name: "On Time Clinic", credit_terms_days: 30)
    [[late, 40.days.ago.to_date], [on_time, Date.current]].each do |customer, date|
      invoice = CustomerInvoice.create!(company: company, customer: customer, user: owner,
                                        location: location, invoice_date: date)
      invoice.update_columns(total_cents: 1_000_00, status: "confirmed", payment_status: "unpaid")
    end

    get receivable_admin_accounting_aging_reports_path
    expect(response.body).to include('role="switch"', 'aria-checked="false"', "On Time Clinic")

    get receivable_admin_accounting_aging_reports_path(overdue_only: 1)
    expect(response.body).to include('aria-checked="true"', "Late Clinic")
    expect(response.body).not_to include("On Time Clinic")
    expect(response.body).to include(receivable_admin_accounting_aging_reports_path(format: :csv, overdue_only: 1))
    expect(response.body).to include(CGI.escapeHTML(receivable_admin_accounting_aging_reports_path(overdue_only: 1, print: 1)))

    get receivable_admin_accounting_aging_reports_path(format: :csv, overdue_only: 1)
    expect(response.body.lines.first).to include(I18n.t("accounting.aging.overdue_only"))
    expect(response.body).to include("Late Clinic")
    expect(response.body).not_to include("On Time Clinic")
  end

  it "exports CSV with plain decimal amounts" do
    customer = create(:customer, company: company, name: "Clinic")
    invoice = CustomerInvoice.create!(company: company, customer: customer, user: owner,
                                      location: location, invoice_date: Date.current)
    invoice.update_columns(total_cents: 1_234_50, status: "confirmed", payment_status: "unpaid")

    get receivable_admin_accounting_aging_reports_path(format: :csv)

    expect(response.media_type).to eq("text/csv")
    expect(response.body).to include("Clinic,1,1234.50")
  end

  it "is listed in the Reports hub" do
    get admin_reports_path

    expect(response.body).to include(receivable_admin_accounting_aging_reports_path)
    expect(response.body).to include(payable_admin_accounting_aging_reports_path)
  end

  it "hides receivables aging from companies that do not sell on credit" do
    restaurant = create(:company, business_type: "restaurant")
    Current.company = restaurant
    sign_in create(:user, :owner, company: restaurant, wages_account_code: 2502)

    get receivable_admin_accounting_aging_reports_path

    expect(response).not_to have_http_status(:ok)
  end

  it "needs the accounting:reports permission" do
    cashier = create(:user, company: company, wages_account_code: 2503)
    sign_in cashier

    get payable_admin_accounting_aging_reports_path

    expect(response).not_to have_http_status(:ok)
  end
end
