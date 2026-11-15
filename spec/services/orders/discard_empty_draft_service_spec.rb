# frozen_string_literal: true

require "rails_helper"

RSpec.describe Orders::DiscardEmptyDraftService do
  let(:company) { create(:company) }
  let(:branch) { create(:location, company: company) }
  let(:cashier) { create(:user, company: company, role: "cashier") }

  before { Current.company = company }

  def order(status: "draft", **attrs)
    create(:order, user: cashier, company: company, location: branch, status: status, **attrs)
  end

  it "deletes an empty draft and leaves an audit entry" do
    empty = order(notes: "call first")

    expect { expect(described_class.call(empty, user: cashier)).to be(true) }
      .to change(Order, :count).by(-1)

    entry = AuditLogEntry.find_by(action: "order.discard_empty", record_id: empty.id)
    expect(entry.user).to eq(cashier)
    expect(entry.changes_snapshot["order_type"]).to eq(empty.order_type)
  end

  it "keeps a draft with items" do
    kept = order
    create(:order_item, order: kept)

    expect(described_class.call(kept)).to be(false)
    expect(Order.exists?(kept.id)).to be(true)
  end

  it "keeps a draft that has taken money" do
    kept = order
    create(:payment, order: kept, amount_cents: 500, status: "completed")

    expect(described_class.call(kept)).to be(false)
    expect(Order.exists?(kept.id)).to be(true)
  end

  it "keeps a placed order reopened for edit" do
    kept = order(unlocked_for_edit_at: Time.current)

    expect(described_class.call(kept)).to be(false)
  end

  it "keeps orders past draft" do
    expect(described_class.call(order(status: "submitted"))).to be(false)
  end

  it "matches the empty_drafts and without_empty_drafts scopes" do
    empty = order
    full = order
    create(:order_item, order: full)
    paid = order
    create(:payment, order: paid, amount_cents: 500, status: "completed")

    expect(Order.empty_drafts).to contain_exactly(empty)
    expect(Order.without_empty_drafts).to contain_exactly(full, paid)
    expect(empty.empty_draft?).to be(true)
    expect(full.empty_draft?).to be(false)
  end
end
