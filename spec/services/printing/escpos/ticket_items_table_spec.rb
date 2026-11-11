# frozen_string_literal: true

require "rails_helper"

RSpec.describe Printing::Escpos::TicketItemsTable do
  let(:builder) do
    Printing::Escpos::ProductionTicketBuilder.new(nil, printer: Printer.new(paper_width: "80mm"),
                                                       order_items: [], title: "Grill")
  end

  def item(modifiers: [], notes: nil)
    mods = modifiers.map { |name| instance_double(OrderItemModifier, name: name) }
    instance_double(OrderItem, order_item_modifiers: mods, notes: notes)
  end

  def lines_for(...) = builder.send(:detail_lines, item(...))

  it "puts every modifier and the note on one line" do
    expect(lines_for(modifiers: %w[Double Cheese], notes: "no sauce"))
      .to eq(["+ Double • Cheese | no sauce"])
  end

  it "prints only the modifiers, or only the note, when that is all there is" do
    expect(lines_for(modifiers: %w[Double])).to eq(["+ Double"])
    expect(lines_for(notes: "  well   done ")).to eq(["well done"])
  end

  it "prints nothing for a plain item" do
    expect(lines_for).to eq([])
  end

  it "never ends a wrapped line on a separator" do
    lines = described_class.wrap("+ Double • Cheese | no sauce", 18)
    expect(lines).to eq(["+ Double • Cheese", "| no sauce"])
    expect(lines).to all(satisfy { |line| !line.end_with?("|", "•", "+") })
  end

  it "wraps a long line at word boundaries instead of running off the paper" do
    lines = lines_for(modifiers: Array.new(8) { |i| "Extra topping #{i}" }, notes: "cut in half please")
    limit = (42 * described_class::DETAIL_CHARS_RATIO).floor

    expect(lines.size).to be > 1
    expect(lines).to all(satisfy { |line| line.length <= limit })
    expect(lines.join(" ")).to eq("+ #{Array.new(8) { |i| "Extra topping #{i}" }.join(' • ')} | cut in half please")
  end
end
