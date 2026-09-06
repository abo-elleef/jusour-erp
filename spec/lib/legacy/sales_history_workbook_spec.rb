# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("lib/legacy/sales_history_workbook")

RSpec.describe Legacy::SalesHistoryWorkbook do
  subject(:workbook) { described_class.new("unused.xlsx") }

  # Cell values are shared-string indexes (t="s") or inline numbers, exactly as the
  # legacy export writes them. Rows are numbered as in a real (page-broken) sheet.
  let(:strings) do
    ["التاريخ", "اسم الصنف", "فاتورة المبيعات", "فاتورة مردود المبيعات",
     "عملاء- ماي دريم", "01/1/3/205", "المخزن الرئيسي", "Bond Flipro 6ml", "قطعة"]
  end

  let(:shared_xml) do
    "<sst>#{strings.map { |s| "<si><t>#{s}</t></si>" }.join}</sst>"
  end

  def cell(ref, value, shared: false)
    %(<c r="#{ref}"#{shared ? ' t="s"' : ''}><v>#{value}</v></c>)
  end

  let(:sheet_xml) do
    [
      # a repeated page-header label row, which must be ignored
      cell("BT21", 0, shared: true), cell("AD25", 1, shared: true),
      # document row
      cell("BT23", "2026/01/03"), cell("BF23", "2052"), cell("BP23", 2, shared: true),
      cell("AU23", "115250.00"), cell("AY23", 4, shared: true), cell("BD23", 5, shared: true),
      cell("BJ23", 6, shared: true),
      # its single item row
      cell("AN26", "35"), cell("AD26", 7, shared: true), cell("Y26", 8, shared: true),
      cell("Q26", "50.00"), cell("M26", "1730.00"), cell("F26", "86500.00"),
      # a return, later in the file
      cell("BT30", "2026/01/10"), cell("BF30", "139"), cell("BP30", 3, shared: true),
      cell("AU30", "8874.00"), cell("AY30", 4, shared: true), cell("BD30", 5, shared: true),
      cell("AN31", "7"), cell("AD31", 7, shared: true), cell("Q31", "12.00"),
      cell("M31", "493.00"), cell("F31", "5916.00")
    ].join
  end

  before do
    allow(workbook).to receive(:entry).with(described_class::SHEET_XML).and_return(sheet_xml)
    allow(workbook).to receive(:entry).with(described_class::STRINGS_XML).and_return(shared_xml)
  end

  it "reads documents with their line items, skipping page-header labels" do
    documents = workbook.documents

    expect(documents.size).to eq(2)
    expect(documents.map(&:number)).to eq(%w[2052 139])
    expect(documents.map(&:type)).to eq(%w[invoice return])
    expect(documents.first.lines.size).to eq(1)
  end

  it "normalizes the date and splits the account into a code and a name" do
    doc = workbook.documents.first

    expect(doc.date).to eq("2026-01-03")
    expect(doc.customer_code).to eq("205")
    expect(doc.customer_name).to eq("ماي دريم")
    expect(doc.total).to eq("115250.00")
  end

  it "flattens to one row per line item, repeating the document fields" do
    rows = workbook.to_rows

    expect(rows.size).to eq(2)
    expect(rows.first).to eq(["invoice", "2052", "2026-01-03", "115250.00", "205", "ماي دريم",
                              "35", "Bond Flipro 6ml", "قطعة", "50.00", "1730.00", "86500.00"])
    expect(rows.last.first(2)).to eq(["return", "139"])
  end
end
