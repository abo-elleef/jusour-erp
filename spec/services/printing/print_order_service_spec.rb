# frozen_string_literal: true

require "rails_helper"

RSpec.describe Printing::PrintOrderService do
  let(:company) { create(:company) }
  let(:user) { create(:user, company: company) }
  let(:branch) { create(:location, company: company) }

  before { Current.company = company }

  describe "kitchen ticket" do
    let!(:kitchen_printer) do
      Printer.create!(
        company: company,
        location: branch,
        name: "Kitchen",
        printer_type: "kitchen",
        connection_type: "network",
        host: "192.168.1.51",
        port: 9100,
        paper_width: "80mm",
        active: true,
        is_default: true
      )
    end

    before do
      Setting.set("print_routing", Printing::Config::ROUTING_CLIENT)
    end

    it "queues a kitchen print job when order is submitted" do
      order = create(:order, user: user, company: company, location: branch, status: "submitted",
        subtotal_cents: 1500, tax_cents: 0, total_cents: 1500)
      create(:order_item, order: order, unit_price_cents: 1500)

      expect(Turbo::StreamsChannel).to receive(:broadcast_append_to).with(
        "pos_prints_#{company.id}_#{branch.id}",
        hash_including(target: "client-print-queue")
      )

      described_class.call(order: order, print_type: "kitchen")

      log = PrintLog.last
      expect(log.print_type).to eq("kitchen")
      expect(log.status).to eq("pending")
      expect(log.printer).to eq(kitchen_printer)
    end
  end

  describe "receipt" do
    let!(:receipt_printer) do
      Printer.create!(
        company: company,
        location: branch,
        name: "Receipt",
        printer_type: "receipt",
        connection_type: "network",
        host: "192.168.1.50",
        port: 9100,
        paper_width: "80mm",
        active: true,
        is_default: true
      )
    end

    before do
      Setting.set("print_routing", Printing::Config::ROUTING_SERVER)
    end

    it "prints receipt via server routing" do
      order = create(:order, user: user, company: company, location: branch, status: "completed",
        subtotal_cents: 1000, tax_cents: 0, total_cents: 1000)
      create(:order_item, order: order, unit_price_cents: 1000)

      expect(Printing::Drivers::Network).to receive(:print!).and_return(true)
      described_class.call(order: order, print_type: "receipt")
      expect(PrintLog.last.print_type).to eq("receipt")
      expect(PrintLog.last.status).to eq("sent")
    end
  end
  describe "client routing queueing" do
    let!(:receipt_printer) do
      Printer.create!(company: company, location: branch, name: "Receipt", printer_type: "receipt",
                      connection_type: "network", host: "192.168.1.50", port: 9100, paper_width: "80mm",
                      active: true, is_default: true)
    end
    let(:order) do
      create(:order, user: user, company: company, location: branch, status: "completed",
                     subtotal_cents: 1000, tax_cents: 0, total_cents: 1000).tap do |o|
        create(:order_item, order: o, unit_price_cents: 1000)
      end
    end

    before do
      Setting.set("print_routing", Printing::Config::ROUTING_CLIENT)
      allow(Turbo::StreamsChannel).to receive(:broadcast_append_to)
    end

    it "queues the job without building the bytes (the register's payload fetch does that)" do
      expect(Printing::Escpos::ReceiptBuilder).not_to receive(:new)
      described_class.call(order: order, print_type: "receipt")
      expect(PrintLog.last.status).to eq("pending")
    end

    it "swallows an automatic repeat within seconds" do
      described_class.call(order: order, print_type: "receipt")
      expect { described_class.call(order: order, print_type: "receipt") }.not_to change(PrintLog, :count)
    end

    it "never swallows a deliberate reprint" do
      described_class.call(order: order, print_type: "receipt")
      expect { described_class.call(order: order, print_type: "receipt", manual: true) }
        .to change(PrintLog, :count).by(1)
    end
  end
end
