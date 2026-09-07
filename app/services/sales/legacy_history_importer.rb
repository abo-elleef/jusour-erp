# frozen_string_literal: true

module Sales
  # Imports sales history (invoices + returns) exported from the previous system.
  #
  # Everything lands as HISTORICAL: these sales really happened, so they count in the
  # sales reports, but the money and the goods moved before this system existed —
  # replaying them would invent an AR balance (the export shows 0 paid on every row)
  # and drive on-hand deeply negative. The real AR opening balance belongs in a single
  # opening-balance entry, not in 134 replayed invoices.
  #
  # Row hash (string keys), one per line item, document fields repeated:
  #   doc_type       "invoice" | "return"
  #   doc_number     the old system's document number (idempotency key)
  #   doc_date       ISO date
  #   doc_total      the old system's header total (may be < the line sum: an
  #                  un-itemised header discount)
  #   customer_code  legacy account number   customer_name
  #   product_code   product_name  unit_raw  quantity  unit_price  line_value
  #
  # Re-running is safe: a document whose legacy_number already exists is skipped.
  class LegacyHistoryImporter
    UNIT_MAP = { "قطعة" => "pieces", "الوحدة" => "pieces", "piece" => "pieces", "pcs" => "pieces" }.freeze
    DEFAULT_CATEGORY = "Imported products"
    CENT = BigDecimal("0.01")

    Result = Struct.new(:location_name, :customers_created, :customers_backdated,
                        :customers_without_contact, :products_created,
                        :invoices_created, :credit_notes_created, :lines_created,
                        :free_lines, :discount_docs, :skipped_existing,
                        :notes, :errors, :dry_run, keyword_init: true)

    def initialize(rows:, company:, dry_run: true, location: nil, fallback_phone: nil, user: nil)
      @rows = rows
      @company = company
      @dry_run = dry_run
      @location_arg = location.presence
      @fallback_phone = fallback_phone.presence
      @user = user
      @result = Result.new(
        location_name: nil, customers_created: 0, customers_backdated: 0,
        customers_without_contact: 0, products_created: 0, invoices_created: 0,
        credit_notes_created: 0, lines_created: 0, free_lines: 0, discount_docs: 0,
        skipped_existing: 0, notes: [], errors: [], dry_run: dry_run
      )
    end

    def call
      previous = Current.company
      Current.company = @company

      ActiveRecord::Base.transaction do
        @location = resolve_location!
        @recorder = resolve_user!
        @result.location_name = @location.name

        documents = group_documents(@rows)
        backdate_customers(documents)
        documents.each { |doc| import_document(doc) }

        raise ActiveRecord::Rollback if @dry_run
      end

      @result
    ensure
      Current.company = previous
    end

    private

    # --- grouping -----------------------------------------------------------

    # Invoices and returns are separate sequences in the old system, so a document
    # is identified by type *and* number.
    def group_documents(rows)
      rows.group_by { |r| [r["doc_type"].to_s.strip, r["doc_number"].to_s.strip] }
        .map do |(type, number), lines|
          first = lines.first
          {
            type: type == "return" ? "return" : "invoice",
            number: number,
            date: parse_date(first["doc_date"]),
            total: to_decimal(first["doc_total"]),
            customer_code: first["customer_code"].to_s.strip,
            customer_name: first["customer_name"].to_s.strip,
            lines: lines
          }
        end
    end

    # --- customers ----------------------------------------------------------

    def backdate_customers(documents)
      documents.group_by { |d| customer_key(d) }.each do |_key, docs|
        first_date = docs.filter_map { |d| d[:date] }.min
        customer = find_or_create_customer(docs.first)
        next if customer.blank? || first_date.blank?

        next unless customer.created_at.to_date > first_date

        customer.update_columns(created_at: first_date.beginning_of_day)
        @result.customers_backdated += 1
      end
    end

    def customer_key(doc)
      [doc[:customer_code].presence, doc[:customer_name].downcase]
    end

    def find_or_create_customer(doc)
      @customers ||= {}
      key = customer_key(doc)
      return @customers[key] if @customers.key?(key)

      code = doc[:customer_code].presence
      name = doc[:customer_name].presence
      scope = Customer.where(company: @company)
      customer = (code && scope.find_by(legacy_code: code)) ||
                 (name && scope.where("lower(name) = ?", name.downcase).first)

      customer ||= build_customer(code, name)
      @customers[key] = customer
    end

    def build_customer(code, name)
      customer = Customer.new(
        company: @company, name: name, legacy_code: code,
        customer_type: "commercial", phone: @fallback_phone
      )

      if customer.save
        @result.customers_created += 1
      else
        # The export carries no phone/email, which the everyday-customer validation
        # requires. A legacy commercial account identified by its old account number
        # is legitimate without one, so record it — loudly — rather than dropping
        # the customer's whole history. Pass a phone to the task to avoid this.
        customer.save(validate: false)
        @result.customers_created += 1
        @result.customers_without_contact += 1
        @result.notes << "Created \"#{name}\" (legacy #{code}) with no phone/email — " \
                         "add contact details, or re-run with a phone argument."
      end

      customer
    end

    # --- products -----------------------------------------------------------

    def find_or_create_ingredient(row)
      code = row["product_code"].to_s.strip
      name = row["product_name"].to_s.strip
      @ingredients ||= {}
      key = code.presence || name.downcase
      return @ingredients[key] if @ingredients.key?(key)

      scope = Ingredient.where(company: @company)
      ingredient = (code.present? && scope.find_by(code: code)) ||
                   (name.present? && scope.where("lower(name) = ?", name.downcase).first)

      ingredient ||= create_ingredient(code, name, row)
      @ingredients[key] = ingredient
    end

    def create_ingredient(code, name, row)
      ingredient = Ingredient.new(
        company: @company, name: name, code: code.presence || name.parameterize,
        unit: mapped_unit(row["unit_raw"]), ingredient_category: default_category,
        selling_price_cents: to_cents(row["unit_price"])
      )
      ingredient.save!
      @result.products_created += 1
      @result.notes << "Created product #{ingredient.code} — #{ingredient.name}"
      ingredient
    end

    def default_category
      @default_category ||= IngredientCategory.where(company: @company)
        .find_or_create_by!(name: DEFAULT_CATEGORY)
    end

    def mapped_unit(raw)
      key = raw.to_s.strip
      UNIT_MAP[key] || (@company.unit_names.include?(key) ? key : "pieces")
    end

    # --- documents ----------------------------------------------------------

    def import_document(doc)
      return if already_imported?(doc)

      doc[:type] == "return" ? import_credit_note(doc) : import_invoice(doc)
    rescue ActiveRecord::RecordInvalid => e
      @result.errors << { doc: document_label(doc), messages: e.record.errors.full_messages }
    end

    def already_imported?(doc)
      klass = doc[:type] == "return" ? CreditNote : CustomerInvoice
      return false unless klass.where(company: @company, legacy_number: doc[:number]).exists?

      @result.skipped_existing += 1
      true
    end

    def import_invoice(doc)
      customer = find_or_create_customer(doc)
      invoice = CustomerInvoice.create!(
        company: @company, customer: customer, user: @recorder, salesperson: @recorder,
        location: @location, invoice_date: doc[:date], status: "historical",
        payment_status: "unpaid", legacy_number: doc[:number], notes: notes_for(doc)
      )

      doc[:lines].each_with_index do |row, index|
        line = invoice.customer_invoice_lines.create!(line_attributes(row, index))
        preserve_free_line(line, row)
        @result.lines_created += 1
      end

      settle_total(invoice, invoice.customer_invoice_lines)
      backdate(invoice, doc[:date])
      @result.invoices_created += 1
    end

    def import_credit_note(doc)
      customer = find_or_create_customer(doc)
      note = CreditNote.create!(
        company: @company, customer: customer, user: @recorder, location: @location,
        credit_note_date: doc[:date], status: "historical",
        legacy_number: doc[:number], notes: notes_for(doc)
      )

      doc[:lines].each_with_index do |row, index|
        line = note.credit_note_lines.create!(line_attributes(row, index))
        preserve_free_line(line, row)
        @result.lines_created += 1
      end

      settle_total(note, note.credit_note_lines)
      backdate(note, doc[:date])
      @result.credit_notes_created += 1
    end

    def line_attributes(row, index)
      ingredient = find_or_create_ingredient(row)
      {
        ingredient: ingredient,
        unit: unit_for(ingredient, row["unit_raw"]),
        quantity: to_decimal(row["quantity"]),
        unit_price_cents: unit_price_cents(row),
        position: index
      }
    end

    # The old system's price column and its line value disagree on a couple of rows;
    # the value column is what its own document totals reconcile against, so derive
    # the unit price from value ÷ quantity whenever the two conflict.
    def unit_price_cents(row)
      price = to_decimal(row["unit_price"])
      value = to_decimal(row["line_value"])
      quantity = to_decimal(row["quantity"])
      return (price * 100).round if quantity <= 0 || (quantity * price - value).abs <= CENT

      (value / quantity * 100).round
    end

    # A free-of-charge line (bonus goods) is priced at 0 in the export, but
    # CustomerInvoiceLine deliberately backfills a zero price from the product's
    # current selling price. Put the historical 0 back.
    def preserve_free_line(line, row)
      return unless to_decimal(row["unit_price"]).zero? && to_decimal(row["line_value"]).zero?

      line.update_columns(unit_price_cents: 0, line_total_cents: 0)
      @result.free_lines += 1
    end

    # The document total is recomputed from its lines, so re-read them after any
    # free-line correction. Where the old header total was lower (an un-itemised
    # header discount) the difference is recorded in the notes, not silently applied
    # — a draft carries no ledger impact, so the honest number is the line sum.
    def settle_total(document, association)
      association.reload
      document.update_columns(total_cents: association.sum(&:line_total_cents))
    end

    def notes_for(doc)
      parts = ["Legacy #{doc[:type] == 'return' ? 'return' : 'invoice'} ##{doc[:number]}"]
      parts << doc[:date].to_s

      line_sum = doc[:lines].sum { |r| to_decimal(r["line_value"]) }
      discount = line_sum - doc[:total]
      if doc[:total].positive? && discount.abs > CENT
        @result.discount_docs += 1
        parts << format("legacy total %.2f (discount %.2f not itemised)", doc[:total], discount)
      end

      parts.join(" · ")
    end

    def backdate(record, date)
      return if date.blank?

      record.update_columns(created_at: date.beginning_of_day, updated_at: date.beginning_of_day)
    end

    # --- lookups ------------------------------------------------------------

    def resolve_location!
      scope = Location.where(company: @company)
      location = @location_arg && (scope.find_by(id: @location_arg) || scope.find_by(name: @location_arg))
      location ||= scope.ordered.first
      raise ArgumentError, "#{@company.name} has no location to import into" if location.blank?

      location
    end

    def resolve_user!
      user = @user || User.unscoped.where(company: @company).find_by(role: "owner") ||
             User.unscoped.where(company: @company).first
      raise ArgumentError, "#{@company.name} has no user to attribute the import to" if user.blank?

      user
    end

    def unit_for(ingredient, raw)
      name = mapped_unit(raw)
      unit = Unit.where(company: @company).find_by(name: name)
      return nil if unit.blank? || ingredient.blank?

      ingredient.available_units.include?(unit) ? unit : nil
    end

    def document_label(doc)
      "#{doc[:type]} ##{doc[:number]}"
    end

    def parse_date(raw)
      Date.parse(raw.to_s)
    rescue Date::Error, TypeError
      nil
    end

    def to_decimal(value)
      BigDecimal(value.to_s.strip.presence || "0")
    rescue ArgumentError
      BigDecimal("0")
    end

    def to_cents(value)
      (to_decimal(value) * 100).round
    end
  end
end
