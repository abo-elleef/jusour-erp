# frozen_string_literal: true

require "rails_helper"

RSpec.describe Accounting::PdfReportService do
  let(:report) do
    {
      summary: { gross_sales_cents: 1_034_729, discount_cents: 0, tax_cents: 0, tip_cents: 0,
                 net_sales_cents: 1_034_729, order_count: 58, average_ticket_cents: 17_840 },
      by_category: [
        { category: "سندوتشات بيف", revenue_cents: 84_500 },
        { category: "Demo Drinks", revenue_cents: 2_500 }
      ]
    }
  end

  # Was a 500 on production: fixed 200+200 column widths against a full-width
  # table, then the built-in font refusing Arabic category names and currency.
  it "renders a PDF with Arabic category names" do
    pdf = described_class.new(report, Date.new(2026, 11, 1), Date.new(2026, 11, 22), one_branch: true).render

    expect(pdf).to start_with("%PDF")
  end
end
