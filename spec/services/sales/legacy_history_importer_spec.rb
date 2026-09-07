# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sales::LegacyHistoryImporter do
  let(:company) { create(:company) }
  let!(:owner) { create(:user, company: company, role: "owner") }
  let!(:location) { create(:location, company: company, name: "المنصورة") }
  let(:category) { create(:ingredient_category, company: company) }
  let!(:bond) do
    create(:ingredient, company: company, ingredient_category: category,
      code: "35", name: "Bond Flipro 6ml", unit: "pieces", selling_price_cents: 220_000)
  end

  before { Current.company = company }

  def row(overrides = {})
    {
      "doc_type" => "invoice", "doc_number" => "2052", "doc_date" => "2026-01-03",
      "doc_total" => "1000.00", "customer_code" => "205", "customer_name" => "ماي دريم",
      "product_code" => "35", "product_name" => "Bond Flipro 6ml", "unit_raw" => "قطعة",
      "quantity" => "2.00", "unit_price" => "500.00", "line_value" => "1000.00"
    }.merge(overrides)
  end

  def import(rows, **options)
    described_class.new(rows: rows, company: company, dry_run: false,
      location: "المنصورة", **options).call
  end

  it "creates the customer, backdated to their first order" do
    result = import([row("doc_date" => "2026-03-05", "doc_number" => "9"),
                     row("doc_date" => "2026-01-03", "doc_number" => "8")],
      fallback_phone: "01000000001")

    customer = Customer.find_by(legacy_code: "205")
    expect(result.customers_created).to eq(1)
    expect(customer.name).to eq("ماي دريم")
    expect(customer.customer_type).to eq("commercial")
    expect(customer.created_at.to_date).to eq(Date.new(2026, 1, 3))
  end

  it "creates a contactless customer rather than dropping their history" do
    result = import([row])

    expect(result.customers_without_contact).to eq(1)
    expect(result.notes.first).to include("no phone/email")
    expect(Customer.find_by(legacy_code: "205")).to be_present
    expect(CustomerInvoice.count).to eq(1)
  end

  it "imports invoices as historical with the legacy number and no ledger impact" do
    import([row], fallback_phone: "01000000001")

    invoice = CustomerInvoice.sole
    expect(invoice).to be_historical
    expect(invoice.legacy_number).to eq("2052")
    expect(invoice.invoice_date).to eq(Date.new(2026, 1, 3))
    expect(invoice.location).to eq(location)
    expect(invoice.total_cents).to eq(100_000)
    expect(invoice.notes).to include("Legacy invoice #2052")
    expect(StockAdjustment.count).to eq(0)
    expect(JournalEntry.count).to eq(0)
  end

  it "imports a return as a historical credit note" do
    result = import([row("doc_type" => "return", "doc_number" => "139")],
      fallback_phone: "01000000001")

    note = CreditNote.sole
    expect(result.credit_notes_created).to eq(1)
    expect(note).to be_historical
    expect(note.legacy_number).to eq("139")
    expect(note.total_cents).to eq(100_000)
  end

  it "keeps a free-of-charge line at zero instead of backfilling the selling price" do
    result = import([row("unit_price" => "0.00", "line_value" => "0.00")],
      fallback_phone: "01000000001")

    line = CustomerInvoiceLine.sole
    expect(result.free_lines).to eq(1)
    expect(line.unit_price_cents).to eq(0)
    expect(line.line_total_cents).to eq(0)
    expect(CustomerInvoice.sole.total_cents).to eq(0)
  end

  it "derives the unit price from the line value when the two disagree" do
    # The old system prints 1,850 but values the line at 1,650 × qty.
    import([row("quantity" => "30.00", "unit_price" => "1850.00", "line_value" => "49500.00")],
      fallback_phone: "01000000001")

    expect(CustomerInvoiceLine.sole.unit_price_cents).to eq(165_000)
  end

  it "records an un-itemised header discount in the notes without applying it" do
    result = import([row("doc_total" => "950.00")], fallback_phone: "01000000001")

    expect(result.discount_docs).to eq(1)
    expect(CustomerInvoice.sole.notes).to include("discount 50.00 not itemised")
    expect(CustomerInvoice.sole.total_cents).to eq(100_000)
  end

  it "creates a product that does not exist yet" do
    result = import([row("product_code" => "999", "product_name" => "New Composite")],
      fallback_phone: "01000000001")

    expect(result.products_created).to eq(1)
    expect(Ingredient.find_by(code: "999").name).to eq("New Composite")
  end

  it "skips documents that were already imported" do
    import([row], fallback_phone: "01000000001")
    result = import([row], fallback_phone: "01000000001")

    expect(result.skipped_existing).to eq(1)
    expect(result.invoices_created).to eq(0)
    expect(CustomerInvoice.count).to eq(1)
  end

  it "counts a historical sale as realized, but never as outstanding" do
    import([row, row("doc_type" => "return", "doc_number" => "139")],
      fallback_phone: "01000000001")

    expect(CustomerInvoice.realized.count).to eq(1)
    expect(CreditNote.realized.count).to eq(1)
    expect(CustomerInvoice.draft.count).to eq(0)
    expect(CustomerInvoice.confirmed.count).to eq(0)
    expect(CustomerInvoice.outstanding.count).to eq(0)
  end

  it "refuses to confirm a historical invoice" do
    import([row], fallback_phone: "01000000001")
    invoice = CustomerInvoice.sole

    expect {
      Sales::ConfirmCustomerInvoiceService.new(invoice, owner).call
    }.to raise_error(Sales::ConfirmCustomerInvoiceService::Error)

    expect(invoice.reload).to be_historical
    expect(invoice.customer.ar_balance_cents).to eq(0)
    expect(StockAdjustment.count).to eq(0)
  end

  it "writes nothing on a dry run" do
    described_class.new(rows: [row], company: company, dry_run: true, location: "المنصورة").call

    expect(CustomerInvoice.count).to eq(0)
    expect(Customer.where(legacy_code: "205").count).to eq(0)
  end
end
