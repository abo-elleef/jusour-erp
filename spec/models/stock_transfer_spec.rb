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

  it "defaults transferred_on to today and stamps requested_at on that day" do
    t = described_class.create!(
      company: Current.company,
      from_location: kitchen,
      to_location: branch,
      requested_by: manager,
      transferred_on: Date.current - 2
    )

    expect(t.transferred_on).to eq(Date.current - 2)
    expect(t.requested_at.to_date).to eq(Date.current - 2)
  end

  it "rejects a transfer date in the future" do
    t = described_class.new(
      company: Current.company,
      from_location: kitchen,
      to_location: branch,
      requested_by: manager,
      transferred_on: Date.current + 1
    )

    expect(t).not_to be_valid
    expect(t.errors[:transferred_on]).to be_present
  end

  describe "draft status" do
    def build_transfer(status)
      described_class.create!(
        company: Current.company,
        from_location: kitchen,
        to_location: branch,
        requested_by: manager,
        status: status
      )
    end

    it "is editable but neither sendable nor part of the open queue" do
      draft = build_transfer("draft")

      expect(draft).to be_draft
      expect(draft).to be_editable
      expect(draft).to be_can_submit
      expect(draft).to be_discardable
      expect(draft.can_send?).to be(false)
      expect(described_class.in_progress).not_to include(draft)
    end

    it "keeps a submitted transfer out of the discardable set" do
      requested = build_transfer("requested")

      expect(requested).to be_editable
      expect(requested.discardable?).to be(false)
      expect(requested.can_submit?).to be(false)
      expect(described_class.in_progress).to include(requested)
    end

    it "keeps re-syncing requested_at while it is still a draft" do
      draft = build_transfer("draft")

      draft.update!(transferred_on: Date.current - 3)

      expect(draft.reload.requested_at.to_date).to eq(Date.current - 3)
    end
  end

  describe "#stale_awaiting_receipt?" do
    def awaiting(on:)
      described_class.create!(
        company: Current.company, from_location: kitchen, to_location: branch,
        requested_by: manager, status: "awaiting_receipt", transferred_on: on
      )
    end

    it "flags a shipment left unreceived past the aging window" do
      expect(awaiting(on: Date.current - (described_class::AGING_RECEIPT_DAYS + 1))).to be_stale_awaiting_receipt
    end

    it "does not flag one still inside the window" do
      expect(awaiting(on: Date.current - (described_class::AGING_RECEIPT_DAYS - 1))).not_to be_stale_awaiting_receipt
    end

    it "only applies to awaiting_receipt" do
      old_draft = described_class.create!(
        company: Current.company, from_location: kitchen, to_location: branch,
        requested_by: manager, status: "draft", transferred_on: Date.current - 30
      )

      expect(old_draft).not_to be_stale_awaiting_receipt
    end
  end
end
