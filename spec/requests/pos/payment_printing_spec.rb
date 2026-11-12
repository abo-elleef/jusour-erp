# frozen_string_literal: true

require "rails_helper"

RSpec::Matchers.define_negated_matcher :not_have_enqueued_job, :have_enqueued_job

# An order prints once, when it is placed. A payment that places a cart (paid
# straight away) prints the receipt and the kitchen / bar tickets; a payment on an
# order placed earlier prints nothing. There is no opting out at the till.
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

  it "prints the receipt and the kitchen / bar tickets" do
    expect { pay }
      .to have_enqueued_job(Printing::PrintReceiptJob).with(order.id)
      .and have_enqueued_job(Printing::DispatchProductionPrintsJob).with(order.id)
    expect(order.reload.status).to eq("submitted")
  end

  it "ignores the old opt-out fields from a register still running the previous page" do
    expect { pay(print_receipt: "0", print_production: "0") }
      .to have_enqueued_job(Printing::PrintReceiptJob).with(order.id)
      .and have_enqueued_job(Printing::DispatchProductionPrintsJob).with(order.id)
  end

  it "does not send a cart's tickets to the kitchen a second time" do
    order.update_column(:kitchen_sent_at, 5.minutes.ago)

    expect { pay }
      .to have_enqueued_job(Printing::PrintReceiptJob).with(order.id)
      .and not_have_enqueued_job(Printing::DispatchProductionPrintsJob)
    expect(order.reload.status).to eq("submitted")
  end

  context "when the order was placed before it was paid" do
    before do
      Orders::PlaceService.call(order, user: cashier)
      clear_enqueued_jobs
    end

    it "only takes the money: no receipt and no tickets" do
      expect { pay }
        .to change(Payment, :count).by(1)
        .and not_have_enqueued_job(Printing::PrintReceiptJob)
        .and not_have_enqueued_job(Printing::DispatchProductionPrintsJob)
      expect(order.reload).to be_fully_paid
    end

    it "still lets the cashier reprint the receipt from the order page" do
      post print_receipt_pos_order_path(order)
      expect(PrintLog.where(order: order, print_type: "receipt")).to exist
    end
  end

  it "prints nothing for a part payment" do
    expect { pay(amount_cents: order.total_cents / 2) }
      .to change(Payment, :count).by(1)
      .and not_have_enqueued_job(Printing::PrintReceiptJob)
      .and not_have_enqueued_job(Printing::DispatchProductionPrintsJob)
  end

  it "offers no print choices in the payment modal" do
    get pos_order_path(order)
    expect(response.body).not_to include("printReceipt")
    expect(response.body).not_to include("printProduction")
  end
end
