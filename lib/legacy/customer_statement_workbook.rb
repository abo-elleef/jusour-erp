# frozen_string_literal: true

require "bigdecimal"
require "open3"

module Legacy
  # Reads a legacy "كشف حساب: عميل" (Customer Account Statement) workbook exported
  # by the previous system (Sky Soft) — one file per customer, mixing sales
  # invoices/returns (with line items) and payment vouchers (receipts, refunds —
  # no line items) in one chronological ledger, with a running balance.
  #
  # Unlike SalesHistoryWorkbook (one multi-customer "sales details" sheet with
  # fixed column letters), this report's columns shift from file to file — the
  # customer's name pushes everything after it left or right depending on its
  # length. So columns are located by their header label, re-read every time a
  # header row recurs (it repeats on every printed page), rather than hardcoded.
  class CustomerStatementWorkbook
    SHEET_XML = "xl/worksheets/sheet1.xml"
    STRINGS_XML = "xl/sharedStrings.xml"

    DOC_LABELS = { number: "رقم السند", type: "نوع العملية", credit: "دائن",
                   debit: "مدين", date: "التاريخ" }.freeze
    ITEM_LABELS = { code: "رقم الصنف", name: "اسم الصنف", unit: "الوحده",
                    qty: "الكمية", price: "السعر", value: "القيمة" }.freeze

    CUSTOMER_LABEL = "العميل"
    CURRENT_BALANCE_LABEL = "الرصيد الحالي"

    INVOICE_TYPE = "فاتورة المبيعات"
    RETURN_TYPE = "فاتورة مردود المبيعات"
    DOCUMENT_TYPES = { INVOICE_TYPE => "invoice", RETURN_TYPE => "return" }.freeze

    # Same shape as SalesHistoryWorkbook::HEADERS, so the same
    # Sales::LegacyHistoryImporter can consume rows from either report.
    HEADERS = %w[
      doc_type doc_number doc_date doc_total customer_code customer_name
      product_code product_name unit_raw quantity unit_price line_value
    ].freeze

    Document = Struct.new(:type, :number, :date, :total, :customer_code,
                          :customer_name, :lines, keyword_init: true)

    def initialize(path)
      @path = path
    end

    def customer_code
      customer_header[:code]
    end

    def customer_name
      customer_header[:name]
    end

    # => [Document, ...] — invoices and returns only, with their line items.
    # Receipt/payment vouchers have no lines and aren't "documents" here; see
    # #computed_balance_cents for how they still count toward the balance.
    def documents
      parse! unless @documents
      @documents
    end

    # => [[doc_type, doc_number, ...], ...] flat rows, one per line item.
    def to_rows
      documents.flat_map do |doc|
        doc.lines.map do |line|
          [doc.type, doc.number, doc.date, doc.total, customer_code, customer_name,
           line[:code], line[:name], line[:unit], line[:qty], line[:price], line[:value]]
        end
      end
    end

    # Net balance this customer owes us (positive), independently recomputed
    # from every ledger row — invoices, returns, receipts and payments alike —
    # rather than trusted from the sheet's own printed figure (see
    # #reported_current_balance_cents). Debit raises what's owed, credit lowers it.
    def computed_balance_cents
      parse! unless @ledger_rows
      @ledger_rows.sum { |row| to_cents(row[:debit]) - to_cents(row[:credit]) }
    end

    def last_transaction_date
      parse! unless @ledger_rows
      @ledger_rows.filter_map { |row| row[:date] }.max
    end

    # The sheet's own "current balance" header figure, cents, signed so that a
    # credit balance (customer overpaid / we owe them) comes out negative — for
    # cross-checking against #computed_balance_cents, not for direct use.
    def reported_current_balance_cents
      label_row = cells_by_row.values.find { |row| row.value?(CURRENT_BALANCE_LABEL) }
      return nil unless label_row

      label_col = label_row.find { |_col, val| val.to_s.strip == CURRENT_BALANCE_LABEL }&.first
      value = label_row.select { |col, _val| column_index(col) < column_index(label_col) }.values.first
      parse_signed_amount_cents(value)
    end

    private

    def parse!
      @documents = []
      @ledger_rows = []
      current = nil

      cells_by_row.keys.sort.each do |row_number|
        row = cells_by_row[row_number]

        if doc_header_row?(row)
          @doc_cols = column_map(row, DOC_LABELS)
          next
        end

        if item_header_row?(row)
          @item_cols = column_map(row, ITEM_LABELS)
          next
        end

        if @doc_cols && document_row?(row)
          current = record_ledger_row(row)
        elsif @item_cols && current && item_row?(row)
          current.lines << {
            code: row[@item_cols[:code]].to_s.strip, name: row[@item_cols[:name]].to_s.strip,
            unit: row[@item_cols[:unit]].to_s.strip, qty: row[@item_cols[:qty]].to_s.strip,
            price: row[@item_cols[:price]].to_s.strip, value: row[@item_cols[:value]].to_s.strip
          }
        end
      end
    end

    def record_ledger_row(row)
      date = normalize_date(row[@doc_cols[:date]])
      @ledger_rows << { date: date, debit: row[@doc_cols[:debit]], credit: row[@doc_cols[:credit]] }

      type = DOCUMENT_TYPES[row[@doc_cols[:type]].to_s.strip]
      return nil unless type

      total = type == "return" ? row[@doc_cols[:credit]] : row[@doc_cols[:debit]]
      doc = Document.new(
        type: type, number: row[@doc_cols[:number]].to_s.strip, date: date, total: total.to_s.strip,
        customer_code: customer_code, customer_name: customer_name, lines: []
      )
      @documents << doc
      doc
    end

    def doc_header_row?(row)
      row.value?(DOC_LABELS[:number]) && row.value?(DOC_LABELS[:date])
    end

    def item_header_row?(row)
      row.value?(ITEM_LABELS[:name]) && row.value?(ITEM_LABELS[:qty])
    end

    def document_row?(row)
      row.key?(@doc_cols[:number]) && row.key?(@doc_cols[:date])
    end

    def item_row?(row)
      row.key?(@item_cols[:code]) && row.key?(@item_cols[:name])
    end

    # Maps { field => column_letter } from a label row. Values are matched after
    # stripping, since the export pads some labels with trailing spaces.
    def column_map(row, labels)
      labels.to_h { |field, label| [field, row.find { |_col, val| val.to_s.strip == label }&.first] }
    end

    # The header row reads, left to right: [name] [legacy code] "العميل", then —
    # much further right, unrelated to the customer — a second banner ("--------
    # جميع العملـــيات --------" / "نوع العملية") for the transaction table below.
    # The name isn't reliably in one fixed column (it's column B in some files,
    # C in others), so rather than guess by position or length, only look among
    # cells that come BEFORE the "العميل" label itself — that's what excludes
    # the unrelated banner text, which always comes after it.
    def customer_header
      @customer_header ||= begin
        label_row = cells_by_row.values.find { |row| row.value?(CUSTOMER_LABEL) }
        if label_row
          label_col = label_row.find { |_col, val| val.to_s.strip == CUSTOMER_LABEL }&.first
          before_label = label_row.select { |col, _val| column_index(col) < column_index(label_col) }
                            .values.map { |v| v.to_s.strip }.reject(&:blank?)
          code = before_label.find { |v| v.match?(/\A\d+\z/) }
          name = before_label.find { |v| !v.match?(/\A\d+\z/) }
          { code: code, name: name }
        else
          { code: nil, name: nil }
        end
      end
    end

    # "A" -> 1, "Z" -> 26, "AA" -> 27, ...
    def column_index(letter)
      letter.to_s.chars.reduce(0) { |acc, ch| (acc * 26) + (ch.ord - "A".ord + 1) }
    end

    # "2026/01/03" -> "2026-01-03"
    def normalize_date(raw)
      parts = raw.to_s.strip.split(%r{[/-]})
      return nil unless parts.size == 3

      format("%04d-%02d-%02d", *parts.map(&:to_i))
    end

    def to_cents(value)
      (to_decimal(value) * 100).round
    end

    def to_decimal(value)
      digits = value.to_s.strip.gsub(",", "")
      BigDecimal(digits.presence || "0")
    rescue ArgumentError
      BigDecimal("0")
    end

    # "0", "م 8,650.000" (debit/owes us), "د 47,300.000" (credit/we owe them) —
    # strip the Arabic debit/credit prefix before parsing the number itself.
    def parse_signed_amount_cents(raw)
      text = raw.to_s.strip
      return 0 if text.empty?

      sign = text.start_with?("د") ? -1 : 1
      to_cents(text.gsub(/[^\d.]/, "")) * sign
    end

    # { row_number => RowHash }, blanks omitted. RowHash is a plain Hash with an
    # added #value? for "does any column in this row hold this value" (used to
    # spot repeating header/label rows regardless of which column they land in).
    CELL = /<c\s[^>]*?r="([A-Z]+)(\d+)"([^>]*?)(?:\/>|>(.*?)<\/c>)/m
    VALUE = %r{<v[^>]*>(.*?)</v>}m
    INLINE = %r{<t[^>]*>(.*?)</t>}m

    RowHash = Class.new(Hash) do
      def value?(text)
        values.any? { |v| v.to_s.strip == text }
      end
    end

    def cells_by_row
      @cells_by_row ||= begin
        rows = Hash.new { |h, k| h[k] = RowHash.new }

        entry(SHEET_XML).scan(CELL) do |column, row_number, attributes, body|
          next if body.nil?

          raw = body[VALUE, 1] || body[INLINE, 1]
          next if raw.nil?

          value = attributes.include?('t="s"') ? shared_strings[raw.to_i] : unescape(raw)
          next if value.nil? || value.strip.empty?

          rows[row_number.to_i][column] = value
        end

        rows
      end
    end

    def shared_strings
      @shared_strings ||= begin
        xml = begin
          entry(STRINGS_XML)
        rescue RuntimeError
          "" # a workbook with no shared strings stores every value inline
        end

        xml.scan(%r{<si[^>]*>(.*?)</si>}m).map do |(body)|
          unescape(body.scan(INLINE).flatten.join)
        end
      end
    end

    def unescape(text)
      text.gsub("&lt;", "<").gsub("&gt;", ">")
        .gsub("&quot;", '"').gsub("&apos;", "'").gsub("&amp;", "&")
    end

    def entry(name)
      out, err, status = Open3.capture3("unzip", "-p", @path, name)
      raise "Cannot read #{name} from #{@path}: #{err}" unless status.success?

      out.force_encoding("UTF-8")
    end
  end
end
