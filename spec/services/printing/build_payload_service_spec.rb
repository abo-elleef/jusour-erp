# frozen_string_literal: true

require "rails_helper"

RSpec.describe Printing::BuildPayloadService do
  let(:company) { create(:company) }
  let(:branch) { create(:location, company: company) }
  let(:category) { create(:category, company: company) }
  let(:burger) { create(:menu_item, company: company, category: category, name: "Burger") }
  let(:box) { create(:menu_item, company: company, category: category, name: "Box") }

  let(:grill) do
    printer = Printer.create!(company: company, location: branch, name: "Grill", printer_type: "kitchen",
                              connection_type: "network", host: "192.168.1.52", port: 9100,
                              paper_width: "80mm", active: true)
    printer.menu_items << burger
    printer
  end

  let(:expo) do
    Printer.create!(company: company, location: branch, name: "Pick", printer_type: "expo",
                    connection_type: "network", host: "192.168.1.51", port: 9100,
                    paper_width: "80mm", active: true)
  end

  let(:order) do
    order = create(:order, company: company, location: branch, status: "submitted",
                           subtotal_cents: 2000, tax_cents: 0, total_cents: 2000)
    create(:order_item, order: order, menu_item: burger, unit_price_cents: 1000)
    create(:order_item, order: order, menu_item: box, unit_price_cents: 1000)
    order.reload
  end

  before { Current.company = company }

  def ticket_item_names(printer, print_type)
    names = nil
    allow(Printing::Escpos::ProductionTicketBuilder).to receive(:new).and_wrap_original do |original, *args, **kwargs|
      names = kwargs[:order_items].map { |item| item.menu_item.name }
      original.call(*args, **kwargs)
    end
    described_class.call(order: order, printer: printer, print_type: print_type)
    names
  end

  it "prints only the printer's assigned items on a station ticket" do
    expect(ticket_item_names(grill, "station")).to contain_exactly("Burger")
  end

  it "prints the whole order on the pick ticket" do
    expect(ticket_item_names(expo, "pick_station")).to contain_exactly("Burger", "Box")
  end
end
