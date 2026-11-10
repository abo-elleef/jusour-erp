# frozen_string_literal: true

require "rails_helper"

# Lets the cashier fire the kitchen / bar tickets before the order is paid. It is
# print-only: nothing about the order or its payments may change.
RSpec.describe "Sending a draft order to the kitchen", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let!(:branch) { create(:location, company: company, name: "Main Branch") }
  let(:cashier) { create(:user, company: company, role: "cashier") }

  before do
    Current.company = company
    sign_in cashier
  end

  it "dispatches the production prints and leaves the order and payments alone" do
    order = create(:order, user: cashier, company: company, location: branch, status: "draft")
    create(:order_item, order: order)
    order.recalculate_totals!

    expect(Printing::DispatchProductionPrintsService).to receive(:call).with(order: order, manual: true)

    before_state = order.reload.attributes
    expect { post send_to_kitchen_pos_order_path(order, from: "pos") }.not_to change(Payment, :count)
    expect(order.reload.attributes).to eq(before_state)

    expect(response).to redirect_to(pos_path)
    expect(flash[:notice]).to eq(I18n.t("flash.pos.kitchen_queued"))
  end

  it "records when the tickets went out, without touching the order's status or payments" do
    order = create(:order, user: cashier, company: company, location: branch, status: "draft")
    create(:order_item, order: order)
    order.recalculate_totals!
    allow_any_instance_of(Printing::DispatchProductionPrintsService).to receive(:print_pick_station)
    allow_any_instance_of(Printing::DispatchProductionPrintsService).to receive(:print_station_tickets)

    expect { post send_to_kitchen_pos_order_path(order, from: "pos") }.not_to change(Payment, :count)

    order.reload
    expect(order.kitchen_sent_at).to be_within(1.minute).of(Time.current)
    expect(order.status).to eq("draft")
  end
end
