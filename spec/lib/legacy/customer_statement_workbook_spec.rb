# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("lib/legacy/customer_statement_workbook")

RSpec.describe Legacy::CustomerStatementWorkbook do
  subject(:workbook) { described_class.new("unused.xlsx") }

  # Cell values are shared-string indexes (t="s") or inline text, exactly as the
  # legacy export writes them. Column letters mirror a real file (doc columns
  # A/AR/BB/BH/BL, item columns E/M/O/V/AC/AL) — deliberately NOT the same
  # letters SalesHistoryWorkbook expects, since that's the whole point of this
  # report: columns shift from file to file and must be found by label.
  let(:strings) do
    ["رقم السند", "نوع العملية", "دائن", "مدين", "التاريخ",
     "فاتورة المبيعات", "سند قبض من العميل", "فاتورة مردود المبيعات", "سند قبض عام",
     "رقم الصنف", "اسم الصنف", "الوحده", "الكمية", "السعر", "القيمة",
     "قطعة", "Parion UD", "Articulating Paper 80",
     "العميل", "شركة الفيروز | د.محمود ثروت", "الرصيد الحالي"]
  end

  let(:shared_xml) do
    "<sst>#{strings.map { |s| "<si><t>#{s}</t></si>" }.join}</sst>"
  end

  def cell(ref, value, shared: false)
    %(<c r="#{ref}"#{shared ? ' t="s"' : ''}><v>#{value}</v></c>)
  end

  let(:sheet_xml) do
    [
      # customer header block: name + legacy code + current balance
      cell("B11", 19, shared: true), cell("Q11", "7"), cell("Y11", 18, shared: true),
      cell("B14", "م 8,650.000"), cell("X14", 20, shared: true),

      # doc header row
      cell("A23", 0, shared: true), cell("AR23", 1, shared: true), cell("BB23", 2, shared: true),
      cell("BH23", 3, shared: true), cell("BL23", 4, shared: true),

      # invoice + its item
      cell("A25", "5"), cell("AR25", 5, shared: true), cell("BB25", "0.00"),
      cell("BH25", "14750"), cell("BL25", "2024/10/19"),
      cell("E27", 14, shared: true), cell("M27", 13, shared: true), cell("O27", 12, shared: true),
      cell("V27", 11, shared: true), cell("AC27", 10, shared: true), cell("AL27", 9, shared: true),
      cell("E28", "14750.00"), cell("M28", "2950.00"), cell("O28", "5.00"),
      cell("V28", 15, shared: true), cell("AC28", 16, shared: true), cell("AL28", "9"),

      # a receipt (no item lines)
      cell("A32", "137"), cell("AR32", 6, shared: true), cell("BB32", "40000.00"),
      cell("BH32", "0"), cell("BL32", "2024/11/17"),

      # a return + its item
      cell("A42", "18"), cell("AR42", 7, shared: true), cell("BB42", "23520.00"),
      cell("BH42", "0"), cell("BL42", "2025/03/17"),
      cell("E44", 14, shared: true), cell("M44", 13, shared: true), cell("O44", 12, shared: true),
      cell("V44", 11, shared: true), cell("AC44", 10, shared: true), cell("AL44", 9, shared: true),
      cell("E45", "23520.00"), cell("M45", "120.00"), cell("O45", "196.00"),
      cell("V45", 15, shared: true), cell("AC45", 17, shared: true), cell("AL45", "13"),

      # a general receipt, unrelated to any customer invoice/return
      cell("A50", "999"), cell("AR50", 8, shared: true), cell("BB50", "1000.00"),
      cell("BH50", "0"), cell("BL50", "2025/04/01"),

      # a repeated page-header row (page break) with no further data — must not
      # produce a spurious document or crash
      cell("A60", 0, shared: true), cell("AR60", 1, shared: true), cell("BB60", 2, shared: true),
      cell("BH60", 3, shared: true), cell("BL60", 4, shared: true)
    ].join
  end

  before do
    allow(workbook).to receive(:entry).with(described_class::SHEET_XML).and_return(sheet_xml)
    allow(workbook).to receive(:entry).with(described_class::STRINGS_XML).and_return(shared_xml)
  end

  it "extracts the customer's legacy code and name from the header block" do
    expect(workbook.customer_code).to eq("7")
    expect(workbook.customer_name).to eq("شركة الفيروز | د.محمود ثروت")
  end

  it "reads invoices and returns with their line items, skipping receipts" do
    documents = workbook.documents

    expect(documents.size).to eq(2)
    expect(documents.map(&:type)).to eq(%w[invoice return])
    expect(documents.map(&:number)).to eq(%w[5 18])
    expect(documents.first.lines.size).to eq(1)
    expect(documents.last.lines.size).to eq(1)
  end

  it "takes the invoice/return total from the debit/credit column" do
    invoice, returned = workbook.documents

    expect(invoice.total).to eq("14750")
    expect(returned.total).to eq("23520.00")
  end

  it "flattens to one row per line item, repeating doc and customer fields" do
    rows = workbook.to_rows

    expect(rows.size).to eq(2)
    expect(rows.first).to eq(["invoice", "5", "2024-10-19", "14750", "7", "شركة الفيروز | د.محمود ثروت",
                              "9", "Parion UD", "قطعة", "5.00", "2950.00", "14750.00"])
    expect(rows.last.first(2)).to eq(["return", "18"])
  end

  it "computes the net balance across every ledger row, including receipts" do
    # +14750 (invoice) - 40000 (receipt) - 23520 (return) - 1000 (general receipt)
    expect(workbook.computed_balance_cents).to eq(-49_770_00)
  end

  it "tracks the latest transaction date across every ledger row" do
    expect(workbook.last_transaction_date).to eq("2025-04-01")
  end

  it "parses the sheet's own signed current-balance figure for cross-checking" do
    expect(workbook.reported_current_balance_cents).to eq(8_650_00)
  end

  # Regression: file 0466 has the name in column C (not B, as every other
  # sampled file did) — a page banner ("نوع العملية") sitting further right in
  # the SAME row was briefly mistaken for the name, since it was longer.
  context "when the name lands in a column other than the usual one" do
    let(:sheet_xml) do
      [
        cell("C11", "حمزه أحمد"), cell("O11", "466"), cell("V11", 18, shared: true),
        cell("AQ11", "-------- جميع العملـــيات --------"), cell("BH11", 1, shared: true)
      ].join
    end

    it "still finds the real name, not the unrelated banner text further right" do
      expect(workbook.customer_code).to eq("466")
      expect(workbook.customer_name).to eq("حمزه أحمد")
    end
  end
end
