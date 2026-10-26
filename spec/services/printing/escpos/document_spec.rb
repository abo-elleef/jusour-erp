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
end
