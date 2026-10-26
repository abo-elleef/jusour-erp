# frozen_string_literal: true

require "rails_helper"

RSpec.describe Printing::Escpos::Bidi do
  def visual(text)
    described_class.visual_for_print(text, reshape: false)
  end

  it "reorders Arabic text for LTR printers" do
    expect(described_class.visual_for_print("شكراً لطلبكم")).not_to eq("شكراً لطلبكم")
  end

  it "leaves Latin-only text unchanged" do
    expect(described_class.visual_for_print("ORD-123")).to eq("ORD-123")
  end

  it "reverses Arabic characters into visual order" do
    expect(visual("نوع الطلب: توصيل")).to eq("ليصوت :بلطلا عون")
  end

  it "keeps numbers in reading order inside an Arabic line" do
    expect(visual("12 يونيو 10:48")).to eq("10:48 وينوي 12")
    expect(visual("وجبة العيلة 12 قطعة")).to eq("ةعطق 12 ةليعلا ةبجو")
    expect(visual("يوصل 5.30")).to eq("5.30 لصوي")
  end

  it "keeps Latin words whole inside an Arabic line" do
    expect(visual("وجبة Big Mac")).to eq("Big Mac ةبجو")
  end

  it "mirrors brackets so they still open toward their content" do
    expect(visual("فرايز (كبير)")).to eq("(ريبك) زيارف")
  end

  it "collapses line breaks and surrounding spaces into one line" do
    expect(visual("على الساندتش \n")).to eq("شتدناسلا ىلع")
    expect(described_class.visual_for_print("extra\nsauce ")).to eq("extra sauce")
  end

  it "gives the same result on every call" do
    results = Array.new(50) { described_class.visual_for_print("كولا (كبير) 12 قطعة") }
    expect(results.uniq.size).to eq(1)
  end
end
