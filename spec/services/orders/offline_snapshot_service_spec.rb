# frozen_string_literal: true

require "rails_helper"

RSpec.describe Orders::OfflineSnapshotService do
  let(:company) { create(:company) }
  let(:branch) { create(:location, company: company) }
  let(:cashier) { create(:user, company: company, role: "cashier") }

  before { Current.company = company }

  def workstation(name, created_at)
    Workstation.create!(company: company, location: branch, name: name, created_at: created_at)
  end

  def code_for(station)
    described_class.call(user: cashier, location: branch, workstation: station, csrf_token: "t")[:workstation][:code]
  end

  # Offline order numbers are "OFF-<code><n>"; the code keeps two registers' numbers apart.
  it "gives each register at the branch its own letter, in the order they were added" do
    first = workstation("Front", 2.days.ago)
    second = workstation("Back", 1.day.ago)
    third = workstation("Terrace", 1.hour.ago).tap { |w| w.update!(active: false) }

    expect([code_for(first), code_for(second), code_for(third)]).to eq(%w[A B C])
  end

  it "keeps going past Z" do
    stations = Array.new(28) { |i| workstation("Register #{i}", (30 - i).hours.ago) }

    expect(code_for(stations[25])).to eq("Z")
    expect(code_for(stations[26])).to eq("AA")
    expect(code_for(stations[27])).to eq("AB")
  end

  it "leaves the workstation out when none is chosen" do
    expect(described_class.call(user: cashier, location: branch, workstation: nil, csrf_token: "t")[:workstation]).to be_nil
  end

  it "lists the tables holding an open order so the offline register can warn" do
    branch.update!(table_service: true, table_count: 6)
    order = create(:order, user: cashier, company: company, location: branch, order_type: "table",
                           table_number: "5", status: "submitted")
    create(:order_item, order: order)

    snapshot = described_class.call(user: cashier, location: branch, workstation: nil, csrf_token: "t")

    expect(snapshot[:busy_tables]).to eq("5" => { id: order.id, number: order.order_number })
  end
end
