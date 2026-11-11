# frozen_string_literal: true

require "rails_helper"

RSpec.describe Printing::RasterCache do
  around do |example|
    described_class.enabled = true
    described_class.clear
    example.run
  ensure
    described_class.clear
    described_class.enabled = false
  end

  it "runs the block once per key and returns the kept value afterwards" do
    calls = 0
    2.times { expect(described_class.fetch("k") { calls += 1; "img".b }).to eq("img".b) }

    expect(calls).to eq(1)
  end

  it "never keeps a failed render, so the next call tries again" do
    calls = 0
    2.times { described_class.fetch("k") { calls += 1; nil } }

    expect(calls).to eq(2)
  end

  it "drops the least recently used entry once full" do
    stub_const("#{described_class}::MAX_ENTRIES", 2)
    described_class.fetch("a") { "A" }
    described_class.fetch("b") { "B" }
    described_class.fetch("a") { "unused" } # touch a: b is now the oldest
    described_class.fetch("c") { "C" }

    expect(described_class.size).to eq(2)
    expect(described_class.fetch("a") { "redrawn" }).to eq("A")
    expect(described_class.fetch("b") { "redrawn" }).to eq("redrawn")
  end

  it "does nothing when disabled" do
    described_class.enabled = false
    calls = 0
    2.times { described_class.fetch("k") { calls += 1; "img" } }

    expect(calls).to eq(2)
  end

  describe "with the image renderer" do
    let(:renderer) { Printing::Escpos::ArabicImageRenderer }
    let(:pbm) { "P4\n8 2\n\xFF\x00".b }

    before do
      allow(renderer).to receive(:arabic_font).and_return("/f.ttf")
      allow(Open3).to receive(:capture3).and_return([pbm, "", instance_double(Process::Status, success?: true)])
    end

    it "starts ImageMagick once for the same line, and again for a different one" do
      first = renderer.render_line("مرحبا")
      expect(renderer.render_line("مرحبا")).to eq(first)
      renderer.render_line("شكرا")
      renderer.render_separator
      renderer.render_separator

      expect(Open3).to have_received(:capture3).exactly(3).times
    end
  end

  describe "drawing a document's images in one run" do
    let(:renderer) { Printing::Escpos::ArabicImageRenderer }
    let(:img_a) { "P4\n8 2\n\x01\x02".b }
    let(:img_b) { "P4\n16 1\n\x03\x04".b }
    let(:ok) { instance_double(Process::Status, success?: true) }

    before { allow(renderer).to receive(:arabic_font).and_return("/f.ttf") }

    def compose
      renderer.render_line("مرحبا")
      renderer.render_line("شكرا")
      renderer.render_line("مرحبا")
    end

    it "draws the missing images in a single ImageMagick run and caches each one" do
      allow(Open3).to receive(:capture3).and_return([img_a + img_b, "", ok])

      renderer.prefetch { compose }

      expect(Open3).to have_received(:capture3).once
      batch = RSpec::Mocks.space.proxy_for(Open3).messages_arg_list.first
      expect(batch).to include("-respect-parentheses")
      expect(batch.count("(")).to eq(2)
      expect(renderer.render_line("مرحبا")).to eq(renderer.pbm_to_escpos(img_a))
      expect(renderer.render_line("شكرا")).to eq(renderer.pbm_to_escpos(img_b))
      expect(Open3).to have_received(:capture3).once
    end

    it "leaves everything uncached when the batch output does not match, so each line is drawn alone" do
      allow(Open3).to receive(:capture3).and_return([img_a, "", ok]) # one image back for two asked

      renderer.prefetch { compose }
      renderer.render_line("مرحبا")
      renderer.render_line("شكرا")

      expect(Open3).to have_received(:capture3).exactly(3).times
    end

    it "only asks for what is not cached yet" do
      allow(Open3).to receive(:capture3).and_return([img_a, "", ok])
      renderer.render_line("مرحبا")

      renderer.prefetch { compose } # one image missing: no batch, drawn by the real build

      expect(Open3).to have_received(:capture3).once
    end

    # Real ImageMagick and the bundled Arabic font: the batched receipt must be the
    # very same bytes as the one drawn line by line.
    it "builds an Arabic receipt with the same bytes as drawing each line alone" do
      allow(renderer).to receive(:arabic_font).and_call_original
      company = create(:company)
      branch = create(:location, company: company)
      Current.company = company
      order = create(:order, company: company, location: branch, status: "completed",
                             subtotal_cents: 1000, tax_cents: 0, total_cents: 1000)
      create(:order_item, order: order, unit_price_cents: 1000)
      create(:payment, order: order, payment_method: "cash", status: "completed", amount_cents: 1000)
      printer = Printer.create!(company: company, location: branch, name: "Receipt", printer_type: "receipt",
                                connection_type: "network", host: "192.168.1.50", port: 9100, paper_width: "80mm",
                                active: true)
      allow(Open3).to receive(:capture3).and_call_original
      build = -> { Printing::BuildPayloadService.call(order: order.reload, printer: printer, print_type: "receipt")[:data_base64] }

      I18n.with_locale(:ar) do
        described_class.enabled = false
        plain = build.call
        singles = RSpec::Mocks.space.proxy_for(Open3).messages_arg_list.size

        described_class.enabled = true
        expect(build.call).to eq(plain)
        expect(RSpec::Mocks.space.proxy_for(Open3).messages_arg_list.size - singles).to eq(1) if singles > 1
      end
    end
  end

  describe "the receipt logo" do
    let(:company) { create(:company) }
    let(:branch) { create(:location, company: company) }
    let(:setting) { CompanySetting.where(company: company).first_or_create! }

    before do
      Current.company = company
      setting.receipt_logo.attach(io: File.open(Rails.root.join("spec/fixtures/files/storefront_product.png")),
                                  filename: "c.png", content_type: "image/png")
      allow(Printing::Escpos::ArabicImageRenderer).to receive(:render_logo).and_return("LOGO".b)
    end

    it "downloads and draws the upload once, and again after a new upload" do
      allow(Printing::ReceiptLogo).to receive(:with_source).and_call_original
      2.times { expect(Printing::ReceiptLogo.escpos(location: branch, company: company.reload, doc_width: 42)).to eq("LOGO".b) }
      expect(Printing::ReceiptLogo).to have_received(:with_source).once

      setting.receipt_logo.attach(io: File.open(Rails.root.join("spec/fixtures/files/storefront_product.png")),
                                  filename: "new.png", content_type: "image/png")
      Printing::ReceiptLogo.escpos(location: branch, company: company.reload, doc_width: 42)
      expect(Printing::ReceiptLogo).to have_received(:with_source).twice
    end
  end
end
