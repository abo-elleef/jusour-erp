# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Cashier and station on printed tickets" do
  let(:company) { create(:company) }
  let(:branch) { create(:location, company: company, name: "Cafe") }
  let(:cashier) { create(:user, company: company, role: "cashier", name: "Amir") }
  let(:register) { Workstation.create!(company: company, location: branch, name: "Front Till") }
  let(:printer) do
    Printer.create!(company: company, location: branch, name: "Grill", printer_type: "kitchen",
                    connection_type: "network", host: "192.168.1.60", port: 9100, paper_width: "80mm",
                    active: true, station: "Grill")
  end
  let(:order) { create(:order, user: cashier, company: company, location: branch, workstation: register) }

  before { Current.company = company }

  def text_of(bytes) = bytes.dup.force_encoding("BINARY")

  def expect_issued_by(text, station: "Front Till")
    ["Cashier", "Amir", "Station", station].each do |expected|
      expect(text).to include(expected.b), "expected the ticket to include #{expected.inspect}"
    end
  end

  it "prints them on the kitchen ticket" do
    bytes = I18n.with_locale(:en) { Printing::Escpos::KitchenTicketBuilder.new(order, printer: printer).build }
    expect_issued_by(text_of(bytes))
  end

  it "prints them on station and pick tickets" do
    bytes = I18n.with_locale(:en) do
      Printing::Escpos::ProductionTicketBuilder.new(order, printer: printer, order_items: [], title: "Grill").build
    end
    expect_issued_by(text_of(bytes))
  end

  # A placed order changed with the branch PIN prints again in full; the banner
  # tells the station it replaces the earlier ticket.
  it "marks station tickets EDITED once the order was changed after placing" do
    build = lambda do
      I18n.with_locale(:en) do
        text_of(Printing::Escpos::ProductionTicketBuilder.new(order, printer: printer, order_items: [], title: "Grill").build)
      end
    end
    expect(build.call).not_to include("EDITED".b)

    order.update_column(:edit_count, 2)
    expect(build.call).to include("*** EDITED #2 ***".b)
  end

  it "prints a dash when the order has no register" do
    order.update_column(:workstation_id, nil)
    bytes = I18n.with_locale(:en) { Printing::Escpos::KitchenTicketBuilder.new(order, printer: printer).build }
    expect(text_of(bytes)).to include("Station".b)
    expect(text_of(bytes)).not_to include("Front Till".b)
  end

  it "prints the register on the drawer closing slip" do
    till = Treasury.create!(company: company, name: "Till", treasury_type: "cash_drawer",
                            balance_cents: 0, opening_balance_cents: 0)
    drawer = CashDrawerSession.create!(company: company, user: cashier, treasury: till, location: branch,
                                       session_date: Date.current, opening_float_cents: 0, status: "open")
    bytes = I18n.with_locale(:en) do
      Printing::Escpos::DrawerCloseBuilder.new(drawer, printer: printer, workstation: register).build
    end
    expect_issued_by(text_of(bytes))
  end

  it "prints the branch logo on kitchen, station and drawer prints" do
    allow(Printing::ReceiptLogo).to receive(:escpos).and_return("<<LOGO>>".b)
    till = Treasury.create!(company: company, name: "Till", treasury_type: "cash_drawer",
                            balance_cents: 0, opening_balance_cents: 0)
    drawer = CashDrawerSession.create!(company: company, user: cashier, treasury: till, location: branch,
                                       session_date: Date.current, opening_float_cents: 0, status: "open")
    prints = [
      Printing::Escpos::KitchenTicketBuilder.new(order, printer: printer).build,
      Printing::Escpos::ProductionTicketBuilder.new(order, printer: printer, order_items: [], title: "Grill").build,
      Printing::Escpos::DrawerCloseBuilder.new(drawer, printer: printer).build
    ]
    prints.each { |bytes| expect(text_of(bytes)).to include("<<LOGO>>".b) }
  end

  it "still prints the ticket when the logo cannot be drawn" do
    allow(Printing::ReceiptLogo).to receive(:escpos).and_raise(StandardError, "storage unreachable")
    bytes = I18n.with_locale(:en) { Printing::Escpos::KitchenTicketBuilder.new(order, printer: printer).build }
    expect_issued_by(text_of(bytes))
  end

  it "prints dashes for an order with no branch and no register" do
    order.update_columns(location_id: nil, workstation_id: nil)
    order.reload
    [
      Printing::Escpos::KitchenTicketBuilder.new(order, printer: printer),
      Printing::Escpos::ProductionTicketBuilder.new(order, printer: printer, order_items: [], title: "Grill")
    ].each do |builder|
      text = text_of(I18n.with_locale(:en) { builder.build })
      expect(text).to include("Amir".b)
      expect(text).to include("Station".b)
    end
  end

  it "prints a drawer slip with no register and no branch" do
    till = Treasury.create!(company: company, name: "Till", treasury_type: "cash_drawer",
                            balance_cents: 0, opening_balance_cents: 0)
    drawer = CashDrawerSession.create!(company: company, user: cashier, treasury: till, location: branch,
                                       session_date: Date.current, opening_float_cents: 0, status: "open")
    drawer.update_column(:location_id, nil)
    bytes = I18n.with_locale(:en) { Printing::Escpos::DrawerCloseBuilder.new(drawer.reload, printer: printer).build }
    expect(text_of(bytes)).to include("Station".b)
  end

  it "leaves the customer receipt alone" do
    bytes = I18n.with_locale(:en) { Printing::Escpos::ReceiptBuilder.new(order, printer: printer).build }
    expect(text_of(bytes)).not_to include("Front Till".b)
  end
end
