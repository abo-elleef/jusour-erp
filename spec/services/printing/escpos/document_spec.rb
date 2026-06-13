# frozen_string_literal: true

require "rails_helper"

RSpec.describe Printing::Escpos::Document do
  describe "Arabic encoding" do
    around do |example|
      I18n.with_locale(:ar) { example.run }
    end

    it "encodes Arabic text as Windows-1256 bytes" do
      doc = described_class.new
      doc.text("شكراً")

      bytes = doc.to_bytes
      expect(bytes).to include("\xD4\xDF\xD1\xC7\xF0".b)
      expect(bytes).not_to include("?".b)
    end

    it "selects the Arabic code page during init" do
      doc = described_class.new
      bytes = doc.to_bytes

      expect(bytes).to start_with("\x1B\x40\x1B\x74/\x1B".b)
    end

    it "swaps row columns for RTL layout" do
      doc = described_class.new(width: 20)
      doc.row("label", "99")

      line = doc.to_bytes.split("\n").find { |l| l.include?("99".b) }
      expect(line.index("99".b)).to be < line.index("label".b)
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
