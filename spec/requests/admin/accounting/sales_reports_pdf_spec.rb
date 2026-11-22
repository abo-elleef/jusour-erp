# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Accounting sales report PDF", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let(:owner) { create(:user, :owner, company: company, wages_account_code: 2501) }
  # Arabic names: the PDF once 500'd on them (built-in font has no Arabic).
  let(:mains) { create(:category, company: company, name: "سندوتشات بيف") }
  let(:drinks) { create(:category, company: company, name: "Drinks") }
  let(:range) { { start_date: Date.current, end_date: Date.current } }

  before do
    Current.company = company
    sign_in owner
    burger = create(:menu_item, company: company, category: mains, name: "Burger", base_price_cents: 1000)
    cola = create(:menu_item, company: company, category: drinks, name: "Cola", base_price_cents: 300)
    order = create(:order, user: owner, company: company, status: "completed",
                           subtotal_cents: 2300, total_cents: 2300,
                           created_at: Time.zone.now.change(hour: 12))
    line = create(:order_item, order: order, menu_item: burger, quantity: 2, unit_price_cents: 1000)
    create(:order_item, order: order, menu_item: cola, quantity: 1, unit_price_cents: 300)
    size = ModifierGroup.create!(company: company, name: "Size")
    double = size.modifiers.create!(company: company, name: "Double", price_adjustment_cents: 500)
    line.order_item_modifiers.create!(modifier: double, name: "Double", price_adjustment_cents: 500)
  end

  # The rows the PDF drew, captured from the service the controller built.
  def pdf_rows(params)
    service = nil
    allow(Accounting::PdfReportService).to receive(:new).and_wrap_original do |original, **kwargs|
      service = original.call(**kwargs)
    end
    get admin_accounting_sales_reports_path(range.merge(locale: :en).merge(params).merge(format: :pdf))
    expect(response).to have_http_status(:ok)
    expect(response.body).to start_with("%PDF")
    service.item_rows.map { |kind, name, *| [kind, name] }
  end

  it "lists categories, their items and each item's modifier choices in the grouped view" do
    expect(pdf_rows({})).to eq([
      [:category, "سندوتشات بيف"], [:item, "Burger"], [:group, "Size"], [:choice, "Double"],
      [:category, "Drinks"], [:item, "Cola"],
      [:total, I18n.t("accounting.sales_reports.total", locale: :en)]
    ])
  end

  it "follows the page's flat view and category filter" do
    rows = pdf_rows(item_category: "Drinks")
    expect(rows.map(&:first).uniq).to eq(%i[item total])
    expect(rows).to include([:item, "Cola"])
    expect(rows).not_to include([:item, "Burger"])
  end

  it "follows the page's sort" do
    rows = pdf_rows(view: "flat", sort: "name", dir: "asc").select { |kind, _| kind == :item }
    expect(rows.map(&:last)).to eq(%w[Burger Cola])
  end

  it "labels the PDF in the interface language" do
    %i[ar en].each do |locale|
      rows = pdf_rows(locale: locale)
      expect(rows.last).to eq([:total, I18n.t("accounting.sales_reports.total", locale: locale)])
    end
  end
end
