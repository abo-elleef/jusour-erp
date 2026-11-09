# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Drawer closing slip" do
  let(:company) { create(:company) }
  let(:branch) { create(:location, company: company, name: "Cafe") }
  let(:cashier) { create(:user, company: company, role: "cashier", name: "Amir") }
  let!(:till) do
    Treasury.create!(company: company, name: "Till", treasury_type: "cash_drawer",
                     balance_cents: 0, opening_balance_cents: 0)
  end
  let!(:safe) do
    Treasury.create!(company: company, name: "Safe", treasury_type: "cash_drawer",
                     balance_cents: 0, opening_balance_cents: 0)
  end
  let!(:drawer) do
    CashDrawerSession.create!(company: company, user: cashier, treasury: till, location: branch,
                              session_date: Date.current, opening_float_cents: 10_000, status: "reconciled",
                              expected_cash_cents: 62_000, counted_cash_cents: 61_500, variance_cents: -500,
                              deposit_treasury: safe, created_at: 6.hours.ago)
  end
  let!(:printer) do
    Printer.create!(company: company, location: branch, name: "Front", printer_type: "receipt",
                    connection_type: "network", host: "192.168.1.50", port: 9100, paper_width: "80mm",
                    active: true, is_default: true)
  end

  before do
    Current.company = company
    Setting.set("print_routing", Printing::Config::ROUTING_CLIENT)
  end

  def payment(amount:, method: "cash", status: "completed", refunded: 0)
    order = create(:order, user: cashier, company: company, location: branch, status: "completed")
    create(:payment, order: order, amount_cents: amount, status: status, payment_method: method,
                     refunded_amount_cents: refunded, cash_drawer_session: drawer)
  end

  describe Printing::Escpos::DrawerCloseBuilder do
    def slip_text(reprint: false)
      bytes = I18n.with_locale(:en) { described_class.new(drawer, printer: printer, reprint: reprint).build }
      bytes.dup.force_encoding("BINARY")
    end

    before do
      payment(amount: 50_000)
      payment(amount: 7_500, method: "vodafone_cash")
      payment(amount: 4_000, status: "refunded", refunded: 4_000)
    end

    it "carries the drawer's figures, the refunds and a place to sign" do
      text = slip_text

      ["Drawer closing", "Amir", "Cafe", "Opening float", "100.00", "Total takings", "575.00",
       "Expected cash", "620.00", "Counted cash", "615.00", "Variance", "-5.00", "Safe",
       "Cash refunded", "40.00", "Cashier signature", "Shift manager signature"].each do |expected|
        expect(text).to include(expected.b), "expected the slip to include #{expected.inspect}"
      end
      expect(text).not_to include("REPRINT".b)
    end

    it "is marked as a reprint when it is one" do
      expect(slip_text(reprint: true)).to include("REPRINT".b)
    end
  end

  describe Printing::PrintDrawerCloseService do
    let(:workstation) { Workstation.create!(company: company, location: branch, name: "Till 1", receipt_printer: printer, active: true) }

    it "queues a pending job for the closing register's own stream" do
      expect(Turbo::StreamsChannel).to receive(:broadcast_append_to).with(
        "pos_prints_#{company.id}_#{branch.id}_#{workstation.id}",
        hash_including(target: "client-print-queue", partial: "pos/client_prints/job")
      )

      log = described_class.call(session: drawer, workstation: workstation)

      expect(log).to have_attributes(print_type: "drawer_close", status: "pending", cash_drawer_session_id: drawer.id,
                                     order_id: nil, workstation_id: workstation.id, printer_id: printer.id)
    end

    it "goes to the branch stream when no register is known (a manager closing)" do
      expect(Turbo::StreamsChannel).to receive(:broadcast_append_to).with("pos_prints_#{company.id}_#{branch.id}", anything)
      described_class.call(session: drawer)
    end

    it "logs a skip, and does not raise, when there is no printer" do
      printer.update!(active: false)
      log = nil
      expect { log = described_class.call(session: drawer) }.not_to raise_error
      expect(log).to have_attributes(status: "skipped", error_message: "no_active_receipt_printer")
    end

    it "queues one job for a double tap but a later reprint goes out, flagged as one" do
      allow(Turbo::StreamsChannel).to receive(:broadcast_append_to)

      expect { 2.times { described_class.call(session: drawer) } }.to change(PrintLog, :count).by(1)
      first = PrintLog.last
      expect(described_class.reprint?(first)).to be(false)

      PrintLog.update_all(created_at: 1.minute.ago)
      expect { described_class.call(session: drawer) }.to change(PrintLog, :count).by(1)
      expect(described_class.reprint?(PrintLog.order(:created_at).last)).to be(true)
    end

    it "never lets a failure reach the caller" do
      allow(Turbo::StreamsChannel).to receive(:broadcast_append_to).and_raise("cable down")
      expect { described_class.call(session: drawer) }.not_to raise_error
      expect(PrintLog.where(cash_drawer_session: drawer).pluck(:status)).to include("failed")
    end
  end

  describe PrintLog do
    it "belongs to an order or a drawer, not both and not neither" do
      order = create(:order, user: cashier, company: company, location: branch)
      expect(PrintLog.new(order: order, print_type: "receipt", status: "pending")).to be_valid
      expect(PrintLog.new(cash_drawer_session: drawer, print_type: "drawer_close", status: "pending")).to be_valid
      expect(PrintLog.new(order: order, cash_drawer_session: drawer, print_type: "receipt", status: "pending")).not_to be_valid
      expect(PrintLog.new(print_type: "receipt", status: "pending")).not_to be_valid
    end
  end
end
