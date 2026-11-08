# frozen_string_literal: true

require "rails_helper"

RSpec::Matchers.define_negated_matcher :not_have_enqueued_job, :have_enqueued_job

# What a payment prints is the cashier's call: receipt and kitchen/bar are chosen
# separately, and neither choice may change whether the payment itself goes through.
RSpec.describe "Printing when a payment settles the bill", type: :request do
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

  def pay(amount_cents: order.total_cents, **choices)
    post pos_payments_path, params: {
      order_id: order.id, payment_method: "cash", amount_pounds: (amount_cents / 100.0).to_s
    }.merge(choices)
  end

  it "prints the receipt and the kitchen / bar tickets by default" do
    expect { pay }
      .to have_enqueued_job(Printing::PrintReceiptJob).with(order.id)
      .and have_enqueued_job(Printing::DispatchProductionPrintsJob).with(order.id)
  end

  it "prints only the receipt when kitchen / bar is unticked" do
    expect { pay(print_production: "0") }
      .to have_enqueued_job(Printing::PrintReceiptJob)
      .and not_have_enqueued_job(Printing::DispatchProductionPrintsJob)
    expect(order.reload.status).to eq("submitted")
  end

  it "prints only the kitchen / bar tickets when the receipt is unticked" do
    expect { pay(print_receipt: "0") }
      .to have_enqueued_job(Printing::DispatchProductionPrintsJob)
      .and not_have_enqueued_job(Printing::PrintReceiptJob)
  end

  it "prints nothing, but still takes the payment and submits the order, when both are unticked" do
    expect { pay(print_receipt: "0", print_production: "0") }
      .to change(Payment, :count).by(1)
      .and not_have_enqueued_job(Printing::PrintReceiptJob)
      .and not_have_enqueued_job(Printing::DispatchProductionPrintsJob)

    expect(order.reload.status).to eq("submitted")
    expect(order).to be_fully_paid
  end

  it "prints nothing for a part payment" do
    expect { pay(amount_cents: order.total_cents / 2) }
      .to change(Payment, :count).by(1)
      .and not_have_enqueued_job(Printing::PrintReceiptJob)
      .and not_have_enqueued_job(Printing::DispatchProductionPrintsJob)
  end

  describe "the payment modal" do
    it "starts Kitchen / bar unticked, with the time, once the tickets have gone out" do
      order.update_column(:kitchen_sent_at, Time.zone.local(2026, 11, 9, 14, 32))
      get pos_order_path(order)

      expect(response.body).to include('data-payment-kitchen-sent-value="true"')
      expect(response.body).to include(I18n.t("payment.kitchen_sent_at", time: I18n.l(order.reload.kitchen_sent_at, format: :short_time)))
    end

    it "carries no sent marker for an order never sent" do
      get pos_order_path(order)
      expect(response.body).to include('data-payment-kitchen-sent-value="false"')
    end
  end
end
