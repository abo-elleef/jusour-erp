# frozen_string_literal: true

require "rails_helper"

RSpec.describe Printing::PrintReceiptService do
  let(:company) { create(:company) }
  let(:user) { create(:user, company: company) }
  let(:branch) { create(:location, company: company) }
  let!(:default_printer) do
    Printer.create!(
      company: company,
      location: branch,
      name: "Branch Default",
      printer_type: "receipt",
      connection_type: "network",
      host: "192.168.1.50",
      port: 9100,
      paper_width: "80mm",
      active: true,
      is_default: true
    )
  end
  let!(:register_printer) do
    Printer.create!(
      company: company,
      location: branch,
      name: "Register 1 Printer",
      printer_type: "receipt",
      connection_type: "usb",
      host: "USB001",
      paper_width: "80mm",
      active: true,
      is_default: false
    )
  end
  let!(:workstation) do
    Workstation.create!(
      company: company,
      location: branch,
      name: "Register 1",
      receipt_printer: register_printer,
      active: true
    )
  end

  before { Current.company = company }

  describe "client routing with workstation" do
    before { Setting.set("print_routing", Printing::Config::ROUTING_CLIENT) }

    it "uses the workstation receipt printer and workstation stream" do
      order = create(:order, user: user, company: company, location: branch, workstation: workstation,
        status: "completed", subtotal_cents: 1000, tax_cents: 0, total_cents: 1000)
      create(:order_item, order: order, unit_price_cents: 1000)

      expect(Turbo::StreamsChannel).to receive(:broadcast_append_to).once.with(
        "pos_prints_#{company.id}_#{branch.id}_#{workstation.id}",
        hash_including(target: "client-print-queue")
      )

      described_class.call(order: order)

      log = PrintLog.find_by(print_type: "receipt")
      expect(log.status).to eq("pending")
      expect(log.printer).to eq(register_printer)
    end

    it "falls back to the branch default and location stream without a workstation" do
      order = create(:order, user: user, company: company, location: branch, workstation: nil,
        status: "completed", subtotal_cents: 1000, tax_cents: 0, total_cents: 1000)
      create(:order_item, order: order, unit_price_cents: 1000)

      expect(Turbo::StreamsChannel).to receive(:broadcast_append_to).once.with(
        "pos_prints_#{company.id}_#{branch.id}",
        hash_including(target: "client-print-queue")
      )

      described_class.call(order: order)
      expect(PrintLog.find_by(print_type: "receipt").printer).to eq(default_printer)
    end

    it "queues USB printers through the client agent path" do
      order = create(:order, user: user, company: company, location: branch, workstation: workstation,
        status: "completed", subtotal_cents: 1000, tax_cents: 0, total_cents: 1000)
      create(:order_item, order: order, unit_price_cents: 1000)

      expect(Printing::Drivers::PrintAgent).not_to receive(:print_usb!)
      described_class.call(order: order)
      expect(PrintLog.find_by(print_type: "receipt").status).to eq("pending")
    end
  end

  describe "server routing" do
    before { Setting.set("print_routing", Printing::Config::ROUTING_SERVER) }

    it "sends network printers directly via the network driver" do
      order = create(:order, user: user, company: company, location: branch, status: "completed",
        subtotal_cents: 1000, tax_cents: 0, total_cents: 1000)
      create(:order_item, order: order, unit_price_cents: 1000)

      expect(Printing::Drivers::Network).to receive(:print!).and_return(true)
      described_class.call(order: order)
      expect(PrintLog.find_by(print_type: "receipt").status).to eq("sent")
    end
  end
end
