# frozen_string_literal: true

require "rails_helper"

RSpec.describe Printing::Escpos::ReceiptBuilder do
  let(:company) { create(:company) }
  let(:user) { create(:user, company: company) }
  let(:branch) { create(:location, company: company) }
  let(:printer) do
    Printer.create!(
      company: company,
      location: branch,
      name: "Receipt",
      printer_type: "receipt",
      connection_type: "network",
      host: "192.168.1.50",
      port: 9100,
      paper_width: "80mm",
      active: true
    )
  end
  let(:order) do
    create(:order, user: user, company: company, location: branch,
      order_type: "delivery", status: "completed",
      subtotal_cents: 1000, tax_cents: 0, total_cents: 1000)
  end

  before do
    Current.company = company
    create(:order_item, order: order, unit_price_cents: 1000)
    create(:payment, order: order, payment_method: "cash", status: "completed", amount_cents: 1000)
  end

  it "includes translated order type and payment method" do
    I18n.with_locale(:en) do
      entries = described_class.new(order, printer: printer).build_debug.entries.map { |e| e[:content] || e[:left] }.compact
      expect(entries).to include(a_string_matching(/Order type:.*Delivery/i))
      expect(entries).to include(a_string_matching(/Payments/i))
      expect(entries.join(" ")).to match(/Cash/)
    end
  end

  it "translates order type and payment method for Arabic locale" do
    I18n.with_locale(:ar) do
      entries = described_class.new(order, printer: printer).build_debug.entries.map { |e| e[:content] || e[:left] }.compact
      expect(entries).to include(a_string_matching(/نوع الطلب:.*توصيل/))
      expect(entries).to include(a_string_matching(/المدفوعات/))
      expect(entries.join(" ")).to match(/نقدي/)
    end
  end
end
