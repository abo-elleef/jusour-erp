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

  describe "logo" do
    let(:png) { Rails.root.join("spec/fixtures/files/storefront_product.png") }

    def logo_entries
      described_class.new(order.reload, printer: printer).build_debug.entries.select { |e| e[:kind] == :logo }
    end

    it "prints nothing when no logo is configured" do
      expect(logo_entries).to be_empty
    end

    it "prints the branch logo, or the company logo when the branch has none" do
      setting = CompanySetting.where(company: company).first_or_create!
      setting.receipt_logo.attach(io: File.open(png), filename: "c.png", content_type: "image/png")
      setting.save!
      expect(logo_entries.size).to eq(1)

      branch.receipt_logo.attach(io: File.open(png), filename: "b.png", content_type: "image/png")
      branch.save!
      expect(logo_entries.size).to eq(1)
    end
  end

  it "prints the branch name, and the company name when the order has no branch" do
    company.update!(name: "SAQR Co")
    branch.update!(name: "SAQR Cafe")
    CompanySetting.where(company: company).first_or_create!.update!(restaurant_name: "SAQR Fried Chicken")

    heading = ->(record) {
      described_class.new(record, printer: printer).build_debug.entries.map { |e| e[:content] }
    }

    expect(heading.call(order)).to include("SAQR Cafe")
    expect(heading.call(order)).not_to include("SAQR Fried Chicken")

    order.update!(location: nil)
    expect(heading.call(order.reload)).to include("SAQR Co")
  end

  it "includes translated order type and payment method" do
    I18n.with_locale(:en) do
      entries = described_class.new(order, printer: printer).build_debug.entries.map { |e| e[:content] || e[:left] }.compact
      expect(entries).to include(a_string_matching(/\ADelivery/i))
      expect(entries.join(" ")).not_to match(/Order type/i)
      expect(entries).to include(a_string_matching(/Payments/i))
      expect(entries.join(" ")).to match(/Cash/)
    end
  end

  it "translates order type and payment method for Arabic locale" do
    I18n.with_locale(:ar) do
      entries = described_class.new(order, printer: printer).build_debug.entries.map { |e| e[:content] || e[:left] }.compact
      expect(entries).to include(a_string_matching(/\Aدليفري/))
      expect(entries.join(" ")).not_to match(/نوع الطلب/)
      expect(entries).to include(a_string_matching(/المدفوعات/))
      expect(entries.join(" ")).to match(/نقدي/)
    end
  end

  describe "item details" do
    it "prints every modifier and the note on one line, like the station tickets" do
      item = order.order_items.first
      item.update_column(:notes, "no sauce")
      group = ModifierGroup.create!(company: company, name: "Extras")
      modifier = Modifier.create!(modifier_group: group, name: "Double", price_adjustment_cents: 0)
      %w[Double Cheese].each { |name| item.order_item_modifiers.create!(modifier: modifier, name: name) }

      lines = described_class.new(order.reload, printer: printer).build_debug.entries
                             .filter_map { |e| e[:content] }

      # The receipt's item column is narrow, so this wraps — at a separator, never
      # leaving one dangling at a line end.
      details = lines.map(&:strip)
      expect(details).to include("+ Double • Cheese", "| no sauce")
      expect(details).not_to include("+ Double")
    end
  end

  describe "total without delivery" do
    def rows_for(record)
      described_class.new(record.reload, printer: printer).build_debug.entries
                     .select { |e| %i[text_row image_row].include?(e[:kind]) }
                     .to_h { |e| [e[:left], e[:right]] }
    end

    it "shows the total minus the delivery fee, which the driver keeps" do
      order.update_columns(delivery_fee_cents: 300, total_cents: 1300)

      rows = I18n.with_locale(:en) { rows_for(order) }
      expect(rows["TOTAL"]).to match(/13\.00/)
      expect(rows["Total without delivery"]).to match(/10\.00/)
    end

    it "comes before the delivery fee and the total, after any discount" do
      order.update_columns(discount_cents: 200, delivery_fee_cents: 300, total_cents: 1100)

      labels = I18n.with_locale(:en) { rows_for(order).keys }
      expect(labels.index("Discount")).to be < labels.index("Total without delivery")
      expect(labels.index("Total without delivery")).to be < labels.index("Delivery fee")
      expect(labels.index("Delivery fee")).to be < labels.index("TOTAL")
      expect(I18n.with_locale(:en) { rows_for(order) }["Total without delivery"]).to match(/8\.00/)
    end

    it "is left out when the delivery order has no fee" do
      expect(I18n.with_locale(:en) { rows_for(order) }).not_to have_key("Total without delivery")
    end

    it "is left out on a pickup order" do
      order.update_columns(order_type: "pickup", delivery_fee_cents: 300, total_cents: 1300)

      expect(I18n.with_locale(:en) { rows_for(order) }).not_to have_key("Total without delivery")
    end
  end
end
