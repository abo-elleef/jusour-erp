# frozen_string_literal: true

require "rails_helper"

RSpec.describe Printing::Escpos::Document do
  describe "Arabic encoding" do
    around do |example|
      I18n.with_locale(:ar) { example.run }
    end

    before do
      # Force text-mode encoding tests — stub out image rendering so the
      # specs cover the ESC/POS text path regardless of the local font setup.
      allow(Printing::Escpos::ArabicImageRenderer).to receive(:arabic_font).and_return(nil)
    end

    it "encodes Arabic text as Windows-1256 bytes" do
      doc = described_class.new
      doc.text("شكراً")

      bytes = doc.to_bytes
      expect(bytes).not_to include("?".b)
      expect(bytes).to include("\n".b)
    end

    it "selects the Arabic code page during init" do
      doc = described_class.new
      bytes = doc.to_bytes

      expect(bytes).to start_with("\x1B\x40\x1B\x74/".b)
    end

    it "swaps row columns for RTL layout" do
      doc = described_class.new(width: 20)
      doc.row("label", "99")

      line = doc.to_bytes.split("\n").find { |l| l.include?("99".b) }
      expect(line.index("99".b)).to be < line.index("label".b)
    end

    it "maps left alignment to printer right alignment" do
      doc = described_class.new
      doc.align(:left)

      bytes = doc.to_bytes
      expect(bytes).to include("\x1B\x61\x02".b)
    end

    it "does not reverse pure Latin text" do
      doc = described_class.new
      doc.text("ORD-123")

      bytes = doc.to_bytes
      expect(bytes).to include("ORD-123".b)
    end
  end

  describe "Arabic image lines" do
    around do |example|
      I18n.with_locale(:ar) { example.run }
    end

    before do
      allow(Printing::Escpos::ArabicImageRenderer).to receive(:arabic_font).and_return("/fonts/arabic.ttf")
      allow(Printing::Escpos::ArabicImageRenderer).to receive(:render_line).and_return("IMG".b)
    end

    it "draws the image at double size while double height is on" do
      doc = described_class.new(charset: "utf-8")
      doc.double_height
      doc.text("التجميع")
      doc.double_height(false)
      doc.text("توصيل")

      expect(Printing::Escpos::ArabicImageRenderer).to have_received(:render_line)
        .with(anything, hash_including(font_scale: 2)).once
      expect(Printing::Escpos::ArabicImageRenderer).to have_received(:render_line)
        .with(anything, hash_including(font_scale: 1)).once
    end
  end

  # Regression: raster bytes made the buffer BINARY, and the next non-ASCII text line
  # raised Encoding::CompatibilityError, so the whole receipt was never printed.
  describe "mixing image bytes and non-ASCII text" do
    around do |example|
      I18n.with_locale(:ar) { example.run }
    end

    %w[windows-1256 utf-8].each do |charset|
      it "does not raise after image bytes (#{charset})" do
        allow(Printing::Escpos::ArabicImageRenderer).to receive(:render_logo).and_return("\xFF\xFE\x80".b)
        allow(Printing::Escpos::ArabicImageRenderer).to receive(:arabic_font).and_return(nil)

        doc = described_class.new(charset: charset)
        doc.logo("logo.png")
        expect { doc.text("شكراً ⁩ عنوان") }.not_to raise_error
        doc.cut

        bytes = doc.to_bytes
        expect(bytes.encoding).to eq(Encoding::BINARY)
        expect(bytes).to include("\xFF\xFE\x80".b)
      end
    end

    it "falls back to text when the Arabic image render returns nil" do
      allow(Printing::Escpos::ArabicImageRenderer).to receive(:arabic_font).and_return("/f.ttf")
      allow(Printing::Escpos::ArabicImageRenderer).to receive(:render_logo).and_return("\xFF\x80".b)
      allow(Printing::Escpos::ArabicImageRenderer).to receive(:render_line).and_return(nil)

      doc = described_class.new
      doc.logo("logo.png")
      expect { doc.text("النورده") }.not_to raise_error
    end
  end

  describe "Latin encoding" do
    around do |example|
      I18n.with_locale(:en) { example.run }
    end

    it "encodes text as Windows-1252 bytes" do
      doc = described_class.new
      doc.text("Cafe")

      bytes = doc.to_bytes
      expect(bytes).to include("Cafe".b)
    end

    it "selects the Latin code page during init" do
      doc = described_class.new
      bytes = doc.to_bytes

      expect(bytes).to start_with("\x1B\x40\x1B\x74\x10".b)
    end
  end

  describe "ticket rows" do
    before { allow(Printing::Escpos::ArabicImageRenderer).to receive(:arabic_font).and_return(nil) }

    it "keeps a padded row off the paper edges and prints the quantity bold" do
      doc = described_class.new(width: 20, charset: "latin")
      doc.row("Burger", "2", padded: true, bold_value: true)
      line = doc.to_bytes.split("\n".b).last

      expect(line).to end_with("  Burger         \x1BE\x012\x1BE\x00  ".b)
    end

    it "leaves a plain row as it was" do
      doc = described_class.new(width: 20, charset: "latin")
      doc.row("Total", "9")
      expect(doc.to_bytes.split("\n".b).last).to end_with("\x10Total#{" " * 14}9".b)
    end

    it "asks for padding and a bold value in image mode" do
      allow(Printing::Escpos::ArabicImageRenderer).to receive(:arabic_font).and_return("font.ttf")
      allow(Printing::Escpos::ArabicImageRenderer).to receive(:render_row).and_return("IMG".b)
      described_class.new(charset: "windows-1256", compact: true)
                     .row("برجر", "2", padded: true, bold_value: true, value_column: true)

      expect(Printing::Escpos::ArabicImageRenderer).to have_received(:render_row)
        .with(anything, "2", doc_width: 42, pad: described_class::PAD_DOTS, bold_value: true, bold_label: false,
                             line_factor: Printing::Escpos::ArabicImageRenderer::COMPACT_LINE_FACTOR,
                             value_center_x: (576 * 0.35 / 2).round)
    end

    it "draws a ticket item row bold and larger, in an image tall enough for it" do
      allow(Printing::Escpos::ArabicImageRenderer).to receive(:arabic_font).and_return("font.ttf")
      allow(Printing::Escpos::ArabicImageRenderer).to receive(:capture_pbm).and_return(nil)
      Printing::Escpos::ArabicImageRenderer.render_row("label", "2", doc_width: 42, bold_value: true, bold_label: true,
                                                       line_factor: 1.5)

      renderer = Printing::Escpos::ArabicImageRenderer
      expect(renderer).to have_received(:capture_pbm) do |cmd|
        expect(cmd).to include("576x#{(renderer::BOLD_VALUE_PT * 1.5).round}")
        expect(cmd.each_cons(2).to_a).to include(["-pointsize", renderer::BOLD_LABEL_PT.to_s],
                                                 ["-pointsize", renderer::BOLD_VALUE_PT.to_s])
        expect(cmd.count("-stroke")).to be >= 4
      end
    end

    it "prints a ticket item line bold and double height in text mode" do
      doc = described_class.new(width: 20, charset: "latin")
      doc.row("Burger", "2", padded: true, bold_value: true, bold_label: true)
      line = doc.to_bytes.split("\n".b).last

      expect(line).to include("\x1D!\x11\x1BE\x01  Burger".b)
      expect(line).to end_with("\x1BE\x00\x1D!\x00".b)
    end

    it "draws a ticket's modifier line bold at the item-name size" do
      allow(Printing::Escpos::ArabicImageRenderer).to receive(:arabic_font).and_return("font.ttf")
      allow(Printing::Escpos::ArabicImageRenderer).to receive(:capture_pbm).and_return(nil)
      Printing::Escpos::ArabicImageRenderer.render_modifier_row("+ Double", doc_width: 42, columns: 2, pad: 32,
                                                                line_factor: 1.5, bold: true)

      renderer = Printing::Escpos::ArabicImageRenderer
      expect(renderer).to have_received(:capture_pbm) do |cmd|
        expect(cmd).to include("576x#{(renderer::BOLD_LABEL_PT * 1.5).round}")
        expect(cmd.each_cons(2).to_a).to include(["-pointsize", renderer::BOLD_LABEL_PT.to_s])
        expect(cmd).to include("-stroke")
      end
    end

    it "draws a receipt's modifier line exactly as before" do
      allow(Printing::Escpos::ArabicImageRenderer).to receive(:arabic_font).and_return("font.ttf")
      allow(Printing::Escpos::ArabicImageRenderer).to receive(:capture_pbm).and_return(nil)
      Printing::Escpos::ArabicImageRenderer.render_modifier_row("+ Double", doc_width: 42)

      expect(Printing::Escpos::ArabicImageRenderer).to have_received(:capture_pbm) do |cmd|
        expect(cmd).to include("576x52")
        expect(cmd).not_to include("-stroke")
        expect(cmd.each_cons(5).to_a).to include(["-gravity", "East", "-annotate", "+8+0", "+ Double"])
      end
    end

    it "prints a bold modifier line bold and double height in text mode" do
      doc = described_class.new(width: 20, charset: "latin")
      doc.modifier_text("+ Double", columns: 2, padded: true, bold: true)
      bytes = doc.to_bytes

      expect(bytes).to include("\x1BE\x01\x1D!\x11".b)
      expect(bytes).to include("+ Double".b)
      expect(bytes).to end_with("\x1D!\x00\x1BE\x00".b)
    end

    it "draws receipt rows exactly as before, so their cached images stay valid" do
      allow(Printing::Escpos::ArabicImageRenderer).to receive(:arabic_font).and_return("font.ttf")
      allow(Printing::Escpos::ArabicImageRenderer).to receive(:capture_pbm).and_return(nil)
      Printing::Escpos::ArabicImageRenderer.render_row("label", "9", doc_width: 42)

      expect(Printing::Escpos::ArabicImageRenderer).to have_received(:capture_pbm) do |cmd|
        expect(cmd).to include("576x52")
        expect(cmd.each_cons(4).to_a).to include(["-gravity", "West", "-annotate", "+8+0"])
      end
    end
  end
end
