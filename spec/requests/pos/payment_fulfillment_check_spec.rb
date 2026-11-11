# frozen_string_literal: true

require "rails_helper"

RSpec::Matchers.define_negated_matcher :not_have_enqueued_job, :have_enqueued_job
RSpec::Matchers.define_negated_matcher :not_change, :change

# Paying off a draft submits it to the kitchen, so an order that cannot be submitted
# (table order without a table, delivery without an address) must be refused before
# any money is taken. Taking the money first left a paid draft that never reached
# the kitchen while the customer walked off with a receipt (order 28, 2026-11-11).
RSpec.describe "Payment refuses an order that cannot be submitted", type: :request do
  include ActiveJob::TestHelper
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let!(:branch) { create(:location, company: company) }
  let(:cashier) { create(:user, company: company, role: "cashier") }
  let!(:treasury) do
    Treasury.create!(company: company, name: "Till", treasury_type: "cash_drawer",
                     balance_cents: 0, opening_balance_cents: 0)
  end
  let(:order) do
    o = create(:order, user: cashier, company: company, location: branch, status: "draft")
    create(:order_item, order: o)
    o.recalculate_totals!
    o
  end

  before do
    Current.company = company
    CashDrawerSession.create!(
      company: company, user: cashier, treasury: treasury, location: branch,
      session_date: BusinessDay.today(location: branch), opening_float_cents: 0, status: "open"
    )
    sign_in cashier
  end

  def pay
    post pos_payments_path, params: {
      order_id: order.id, payment_method: "cash", amount_pounds: (order.total_cents / 100.0).to_s
    }
  end

  it "takes no money from a table order without a table number" do
    order.update_columns(order_type: "table", table_number: "")

    expect { pay }
      .to not_change(Payment, :count)
      .and not_have_enqueued_job(Printing::PrintReceiptJob)
      .and not_have_enqueued_job(Printing::DispatchProductionPrintsJob)

    expect(order.reload.status).to eq("draft")
    expect(response).to have_http_status(:see_other)
    expect(flash[:alert]).to eq(I18n.t("order.submit.errors.table_number_required"))
  end

  it "takes no money from a delivery order without an address" do
    order.update_columns(order_type: "delivery", delivery_address: nil)

    expect { pay }.not_to change(Payment, :count)
    expect(order.reload.status).to eq("draft")
    expect(flash[:alert]).to eq(I18n.t("order.submit.errors.delivery_address_required"))
  end

  it "says so in place when the modal posts as a Turbo Stream" do
    order.update_columns(order_type: "table", table_number: "")

    post pos_payments_path,
         params: { order_id: order.id, payment_method: "cash", amount_pounds: (order.total_cents / 100.0).to_s },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include(I18n.t("order.submit.errors.table_number_required"))
    expect(order.payments.count).to eq(0)
  end

  it "takes the money and sends a table order with its table number to the kitchen" do
    order.update_columns(order_type: "table", table_number: "7")

    expect { pay }
      .to change(Payment, :count).by(1)
      .and have_enqueued_job(Printing::DispatchProductionPrintsJob).with(order.id)

    expect(order.reload.status).to eq("submitted")
  end

  it "still takes a later payment on an order already submitted" do
    order.update_columns(order_type: "table", table_number: "7")
    order.submit!
    order.update_columns(table_number: "")

    expect { pay }.to change(Payment, :count).by(1)
  end
end
