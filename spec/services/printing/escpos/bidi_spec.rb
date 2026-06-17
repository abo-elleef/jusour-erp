# frozen_string_literal: true

require "rails_helper"

RSpec.describe Printing::Escpos::Bidi do
  it "reorders Arabic text for LTR printers" do
    expect(described_class.visual_for_print("شكراً لطلبكم")).not_to eq("شكراً لطلبكم")
  end

  it "leaves Latin-only text unchanged" do
    expect(described_class.visual_for_print("ORD-123")).to eq("ORD-123")
  end
end
