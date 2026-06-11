# frozen_string_literal: true

require "rails_helper"

RSpec.describe Printing::PrintReceiptService do
  let(:company) { create(:company) }
  let(:user) { create(:user, company: company) }
  let!(:printer) do
    Printer.create!(
      company: company,
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

  before { Current.company = company }

  describe "client routing" do
    before do
      Setting.set("print_routing", Printing::Config::ROUTING_CLIENT)
    end

    it "creates a pending print log and broadcasts to POS" do
      order = create(:order, user: user, company: company, status: "completed",
        subtotal_cents: 1000, tax_cents: 0, total_cents: 1000)
      create(:order_item, order: order, unit_price_cents: 1000)

      expect(Turbo::StreamsChannel).to receive(:broadcast_append_to).with(
        "pos_prints_#{company.id}",
        hash_including(target: "client-print-queue")
      )

      described_class.call(order: order)

      log = PrintLog.last
      expect(log.status).to eq("pending")
      expect(log.printer).to eq(printer)
    end
  end

  describe "server routing" do
    before do
      Setting.set("print_routing", Printing::Config::ROUTING_SERVER)
    end

    it "sends directly via network driver" do
      order = create(:order, user: user, company: company, status: "completed",
        subtotal_cents: 1000, tax_cents: 0, total_cents: 1000)
      create(:order_item, order: order, unit_price_cents: 1000)

      expect(Printing::Drivers::Network).to receive(:print!).and_return(true)
      described_class.call(order: order)
      expect(PrintLog.last.status).to eq("sent")
    end
  end
end
