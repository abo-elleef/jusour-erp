# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Cash drawer details page", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.zone.local(2026, 6, 10, 14, 0, 0)) { example.run } }

  let(:company) { create(:company) }
  let!(:branch) { create(:location, company: company, name: "Cafe") }
  let(:manager) { create(:user, :manager, company: company) }
  let(:cashier) { create(:user, company: company, role: "cashier", name: "Amir") }
  let!(:till) do
    Treasury.create!(company: company, name: "Till", treasury_type: "cash_drawer",
                     balance_cents: 0, opening_balance_cents: 0)
  end
  let!(:drawer) do
    CashDrawerSession.create!(company: company, user: cashier, treasury: till, location: branch,
                              session_date: Date.current, opening_float_cents: 10_000, status: "open",
                              created_at: 5.hours.ago)
  end

  before do
    Current.company = company
    sign_in manager
  end

  def order_with_payment(amount:, method: "cash", status: "completed", refunded: 0, drawer_id: drawer.id, at: 1.hour.ago)
    order = create(:order, user: cashier, company: company, location: branch, status: "completed")
    create(:payment, order: order, amount_cents: amount, status: status, payment_method: method,
                     refunded_amount_cents: refunded, refund_reason: (refunded.positive? ? "customer cancelled" : nil),
                     processed_by_user: cashier, cash_drawer_session_id: drawer_id, created_at: at)
    order
  end

  it "lists the drawer's payments, refunded ones included and marked, with the counted total" do
    kept = order_with_payment(amount: 5_000)
    wallet = order_with_payment(amount: 2_500, method: "vodafone_cash")
    gone = order_with_payment(amount: 4_000, status: "refunded", refunded: 4_000)

    get admin_accounting_cash_drawer_path(drawer)

    expect(response).to have_http_status(:ok)
    page = Nokogiri::HTML(response.body)
    numbers = page.css("tbody tr td:first-child a").map(&:text)
    expect(numbers).to include("##{kept.order_number}", "##{wallet.order_number}", "##{gone.order_number}")
    expect(page.text).to include("customer cancelled")

    # Only completed payments make the counted figure: 50.00 + 25.00.
    footer = page.at_css("tfoot").text.gsub(/\s+/, " ")
    expect(footer).to include(ApplicationController.helpers.format_amount(7_500))
    expect(footer).to include(ApplicationController.helpers.format_amount(4_000)) # refunded column
  end

  it "does not list another drawer's payments" do
    other = CashDrawerSession.create!(company: company, user: create(:user, company: company, role: "cashier"),
                                      treasury: till, location: branch, session_date: Date.current,
                                      opening_float_cents: 0, status: "open", created_at: 4.hours.ago)
    mine = order_with_payment(amount: 1_000)
    theirs = order_with_payment(amount: 2_000, drawer_id: other.id)

    get admin_accounting_cash_drawer_path(drawer)

    numbers = Nokogiri::HTML(response.body).css("tbody tr td:first-child a").map(&:text)
    expect(numbers).to include("##{mine.order_number}")
    expect(numbers).not_to include("##{theirs.order_number}")
  end

  it "notes a payment a manager attached after the fact" do
    early = create(:order, user: cashier, company: company, location: branch, status: "completed")
    payment = create(:payment, order: early, amount_cents: 3_000, status: "completed", payment_method: "vodafone_cash",
                               processed_by_user: cashier, cash_drawer_session: nil, created_at: 8.hours.ago)
    patch attach_payments_admin_accounting_cash_drawer_path(drawer), params: { payment_ids: [payment.id] }

    get admin_accounting_cash_drawer_path(drawer)

    expect(response.body).to include(I18n.t("accounting.cash_drawer.attached_note", name: manager.name,
                                                                                    time: I18n.l(Time.current, format: :short_time)))
  end

  it "lists counter sales settled on customer invoices" do
    customer = create(:customer, company: company, name: "Shop Co")
    invoice = CustomerInvoice.new(company: company, customer: customer, user: cashier, location: branch, status: "confirmed",
                                  payment_method: "cash", total_cents: 6_000,
                                  confirmed_at: 1.hour.ago, invoice_date: Date.current, invoice_number: "INV-1")
    invoice.save!(validate: false)

    get admin_accounting_cash_drawer_path(drawer)

    expect(response.body).to include("INV-1", "Shop Co")
  end

  it "only reads: nothing about the drawer changes" do
    order_with_payment(amount: 5_000)
    drawer.update_columns(expected_cash_cents: 1, updated_at: 1.day.ago)
    before_state = drawer.reload.attributes

    get admin_accounting_cash_drawer_path(drawer)

    expect(response).to have_http_status(:ok)
    expect(drawer.reload.attributes).to eq(before_state)
  end

  it "is linked from the list" do
    get admin_accounting_cash_drawer_index_path(date: drawer.session_date)
    hrefs = Nokogiri::HTML(response.body).css("a").map { |a| a["href"] }
    expect(hrefs).to include(admin_accounting_cash_drawer_path(drawer))
  end

  it "is not available to a cashier" do
    sign_out manager
    sign_in cashier
    get admin_accounting_cash_drawer_path(drawer)
    expect(response).not_to have_http_status(:ok)
  end
end
