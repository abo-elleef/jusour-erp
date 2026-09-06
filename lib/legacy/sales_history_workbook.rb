# frozen_string_literal: true

require "open3"

module Legacy
  # Reads the "المبيعات - تفاصيل" (Sales - details) workbook exported by the
  # previous system and flattens it into one row per line item.
  #
  # The export is a print layout, not a table: a banner, then repeating blocks of
  # a document row (date / number / type / total / account) followed by its item
  # rows, with page headers sprinkled in. Rows are identified by which columns
  # they carry rather than by position, so extra page breaks don't shift anything.
  #
  # Pure stdlib (the `unzip` binary + a scan of the sheet XML) — no spreadsheet gem
  # needed, and this only ever runs locally, ahead of the import.
  class SalesHistoryWorkbook
    SHEET_XML  = "xl/worksheets/sheet1.xml"
    STRINGS_XML = "xl/sharedStrings.xml"

    # Document row columns
    DOC = { date: "BT", number: "BF", type: "BP", total: "AU", gross: "AR",
            paid: "AL", account_name: "AY", account_code: "BD", warehouse: "BJ" }.freeze
    # Item row columns
    ITEM = { code: "AN", name: "AD", unit: "Y", qty: "Q", price: "M", value: "F" }.freeze

    # Label rows repeat on every printed page; skip anything carrying them.
    DATE_LABEL = "التاريخ"
    ITEM_LABEL = "اسم الصنف"
    RETURN_MARKER = "مردود"

    HEADERS = %w[
      doc_type doc_number doc_date doc_total customer_code customer_name
      product_code product_name unit_raw quantity unit_price line_value
    ].freeze

    Document = Struct.new(:type, :number, :date, :total, :customer_code,
                          :customer_name, :lines, keyword_init: true)

    def initialize(path)
      @path = path
    end

    # => [Document, ...] in file order
    def documents
      rows = cells_by_row
      docs = []
      current = nil

      rows.keys.sort.each do |row_number|
        row = rows[row_number]

        if document_row?(row)
          current = Document.new(
            type: row[DOC[:type]].to_s.include?(RETURN_MARKER) ? "return" : "invoice",
            number: row[DOC[:number]].to_s.strip,
            date: normalize_date(row[DOC[:date]]),
            total: row[DOC[:total]].to_s.strip,
            customer_code: account_code(row[DOC[:account_code]]),
            customer_name: account_name(row[DOC[:account_name]]),
            lines: []
          )
          docs << current
        elsif item_row?(row) && current
          current.lines << {
            code: row[ITEM[:code]].to_s.strip,
            name: row[ITEM[:name]].to_s.strip,
            unit: row[ITEM[:unit]].to_s.strip,
            qty: row[ITEM[:qty]].to_s.strip,
            price: row[ITEM[:price]].to_s.strip,
            value: row[ITEM[:value]].to_s.strip
          }
        end
      end

      docs
    end

    # => [[doc_type, doc_number, ...], ...] flat rows, one per line item
    def to_rows
      documents.flat_map do |doc|
        doc.lines.map do |line|
          [doc.type, doc.number, doc.date, doc.total, doc.customer_code, doc.customer_name,
           line[:code], line[:name], line[:unit], line[:qty], line[:price], line[:value]]
        end
      end
    end

    private

    def document_row?(row)
      row.key?(DOC[:date]) && row.key?(DOC[:number]) && row[DOC[:date]].to_s.strip != DATE_LABEL
    end

    def item_row?(row)
      row.key?(ITEM[:code]) && row.key?(ITEM[:name]) && row[ITEM[:name]].to_s.strip != ITEM_LABEL
    end

    # "01/1/3/205" -> "205" (the customer's account number in the old chart)
    def account_code(raw)
      raw.to_s.strip.split("/").last.to_s.strip
    end

    # "عملاء- ماي دريم" -> "ماي دريم"
    def account_name(raw)
      raw.to_s.strip.sub(/\A[^-]*-\s*/, "").strip
    end

    # "2026/01/03" -> "2026-01-03"
    def normalize_date(raw)
      parts = raw.to_s.strip.split(%r{[/-]})
      return raw.to_s.strip unless parts.size == 3

      format("%04d-%02d-%02d", *parts.map(&:to_i))
    end

    # { row_number => { "AU" => "115250.00", ... } }, blanks omitted.
    #
    # Scanned rather than DOM-parsed: the sheet XML is machine-generated and flat
    # (<c r="AU23" t="s"><v>7</v></c>), and scanning keeps this free of any gem.
    CELL = /<c\s[^>]*?r="([A-Z]+)(\d+)"([^>]*?)(?:\/>|>(.*?)<\/c>)/m
    VALUE = %r{<v[^>]*>(.*?)</v>}m
    INLINE = %r{<t[^>]*>(.*?)</t>}m

    def cells_by_row
      rows = {}

      entry(SHEET_XML).scan(CELL) do |column, row_number, attributes, body|
        next if body.nil?

        raw = body[VALUE, 1] || body[INLINE, 1]
        next if raw.nil?

        value = attributes.include?('t="s"') ? shared_strings[raw.to_i] : unescape(raw)
        next if value.nil? || value.strip.empty?

        (rows[row_number.to_i] ||= {})[column] = value
      end

      rows
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
