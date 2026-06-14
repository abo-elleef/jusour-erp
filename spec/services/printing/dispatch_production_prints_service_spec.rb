# frozen_string_literal: true

require "rails_helper"

RSpec.describe Printing::DispatchProductionPrintsService do
  let(:company) { create(:company) }
  let(:user) { create(:user, company: company) }
  let(:category) { create(:category, company: company) }
  let(:burger) { create(:menu_item, company: company, category: category, name: "Burger") }
  let(:fries) { create(:menu_item, company: company, category: category, name: "Fries") }

  let!(:expo_printer) do
    Printer.create!(
      company: company, name: "Pick", printer_type: "expo",
      connection_type: "network", host: "192.168.1.51", port: 9100,
      paper_width: "80mm", active: true, is_default: true
    )
  end

  let!(:grill_printer) do
    printer = Printer.create!(
      company: company, name: "Grill", printer_type: "kitchen", location: "Grill",
      connection_type: "network", host: "192.168.1.52", port: 9100,
      paper_width: "80mm", active: true, is_default: true
    )
    printer.menu_items << burger
    printer
  end

  let!(:fryer_printer) do
    printer = Printer.create!(
      company: company, name: "Fryer", printer_type: "kitchen",
      connection_type: "network", host: "192.168.1.53", port: 9100,
      paper_width: "80mm", active: false, is_default: false
    )
    printer.menu_items << fries
    printer
  end

  before do
    Current.company = company
    Setting.set("print_routing", Printing::Config::ROUTING_SERVER)
  end

  it "prints pick ticket and station tickets for matching items" do
    order = create(:order, user: user, company: company, status: "submitted",
      subtotal_cents: 2000, tax_cents: 0, total_cents: 2000)
    create(:order_item, order: order, menu_item: burger, unit_price_cents: 1000)
    create(:order_item, order: order, menu_item: fries, unit_price_cents: 1000)

    expect(Printing::Drivers::Network).to receive(:print!).twice.and_return(true)

    described_class.call(order: order)

    logs = PrintLog.order(:created_at)
    expect(logs.map(&:print_type)).to eq(%w[pick_station station])
    expect(logs.map { |l| l.printer.name }).to eq(%w[Pick Grill])
    expect(logs.map(&:status)).to all(eq("sent"))
  end
end
