# frozen_string_literal: true

require "rails_helper"

RSpec.describe StockTransfer, type: :model do
  let(:kitchen) { create(:location, :central_kitchen) }
  let(:branch) { create(:location) }
  let(:manager) { create(:user, :manager) }

  def transfer(number:)
    StockTransfer.create!(company: Current.company, from_location: kitchen, to_location: branch,
      requested_by: manager, requested_at: Time.current, status: "requested", transfer_number: number)
  end

  describe ".next_transfer_number" do
    it "returns a yearly ST sequence for the company" do
      expect(described_class.next_transfer_number(year: 2026)).to eq("ST-2026-00001")
      transfer(number: "ST-2026-00001")
      expect(described_class.next_transfer_number(year: 2026)).to eq("ST-2026-00002")
    end

    it "resets the sequence for a new year" do
      transfer(number: "ST-2026-00009")
      expect(described_class.next_transfer_number(year: 2027)).to eq("ST-2027-00001")
    end

    it "ignores legacy dated numbers when starting the yearly series" do
      transfer(number: "ST-2026-07-11-0001")
      expect(described_class.next_transfer_number(year: 2026)).to eq("ST-2026-00001")
    end
  end

  it "auto-assigns an ST-<year>-<sequence> number on create when blank" do
    t = transfer(number: nil)
    expect(t.transfer_number).to match(/\AST-\d{4}-\d{5}\z/)
  end
end
