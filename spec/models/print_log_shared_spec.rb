# frozen_string_literal: true

require "rails_helper"

# Shared jobs go to every register at the branch; addressed ones to one register.
# A register with a dead print agent stands aside only for shared jobs.
RSpec.describe PrintLog, "#shared?" do
  let(:company) { create(:company) }
  let(:user) { create(:user, company: company) }
  let(:branch) { create(:location, company: company) }
  let(:register) { Workstation.create!(company: company, location: branch, name: "Front") }
  let(:order) { create(:order, user: user, company: company, location: branch, workstation: register) }

  before { Current.company = company }

  def log(print_type, **attrs)
    PrintLog.new(order: order, print_type: print_type, status: "pending", **attrs)
  end

  it "is true for kitchen, station and expo tickets" do
    %w[kitchen bar station pick_station expo].each do |type|
      expect(log(type)).to be_shared, type
    end
  end

  it "is false for a receipt addressed to the order's register" do
    expect(log("receipt")).not_to be_shared
  end

  it "is true for a receipt of an order with no register" do
    order.update_columns(workstation_id: nil)
    expect(log("receipt")).to be_shared
  end

  it "follows the drawer slip's own register" do
    session = instance_double(CashDrawerSession, location_id: branch.id, company_id: company.id)
    slip = PrintLog.new(print_type: "drawer_close", status: "pending", workstation: register)
    allow(slip).to receive(:cash_drawer_session).and_return(session)
    expect(slip).not_to be_shared
    slip.workstation = nil
    expect(slip).to be_shared
  end

  it "matches the stream the job is announced on" do
    expect(log("receipt").stream_name).to end_with("_#{register.id}")
    expect(log("station").stream_name).to eq("pos_prints_#{company.id}_#{branch.id}")
  end
end
