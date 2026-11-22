# frozen_string_literal: true

require "rails_helper"

RSpec.describe Order, "source" do
  it "accepts only the known sources" do
    expect(described_class::SOURCES).to eq(%w[pos offline online call_center])
    order = described_class.new(source: "telepathy")
    order.validate
    expect(order.errors[:source]).to be_present

    order.source = "online"
    order.validate
    expect(order.errors[:source]).to be_empty
  end

  it "defaults to pos" do
    expect(described_class.new.source).to eq("pos")
  end
end
