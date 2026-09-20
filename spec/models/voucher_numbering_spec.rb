# frozen_string_literal: true

require "rails_helper"

# A voucher book has to be auditable: a number is handed out once, and a gap in
# the sequence is explained by a document somebody can open.
#
# Editing an expense used to destroy its voucher and issue a new one, which broke
# that two different ways. `next_number` takes MAX + 1, so destroying the highest
# voucher let the next one REUSE its number — a سند already printed and handed
# over could be reissued at a different amount under the same number. Destroying
# an older one left a hole with nothing in it.
RSpec.describe "Voucher numbering" do
  let(:company) { Current.company }
  let(:user)    { create(:user) }
  let(:cash) do
    Treasury.create!(name: "Cash", treasury_type: "cash_drawer", balance_cents: 900_000,
                     opening_balance_cents: 900_000, company: company)
  end
  let(:category) do
    ExpenseCategory.create!(name: "Rent", category_type: "rent", position: 1, company: company)
  end

  def expense!(description, cents)
    Expense.create!(company: company, user: user, treasury: cash, expense_category: category,
                    description: description, amount_cents: cents, expense_date: Date.current)
  end

  def voucher_for(expense) = expense.reload.payment_allocations.sole.payment

  it "never hands the same number out twice, even editing the newest voucher" do
    first  = expense!("first", 1_000)
    latest = expense!("latest", 3_000)
    original = voucher_for(latest)

    latest.update!(amount_cents: 3_500)

    replacement = voucher_for(latest)
    expect(replacement.number).not_to eq(original.number)
    expect(Voucher.pluck(:number).uniq.size).to eq(Voucher.count)
    expect(first).to be_present
  end

  it "leaves a gap that points at the document explaining it" do
    oldest = expense!("oldest", 1_000)
    expense!("middle", 2_000)
    expense!("newest", 3_000)
    original = voucher_for(oldest)

    oldest.update!(amount_cents: 1_500)

    expect(original.reload).to be_voided
    expect(original.voided_reason).to eq("superseded")
    expect(original.replaced_by).to eq(voucher_for(oldest))
    # The number is still in the book, so the sequence has no silent hole.
    expect(Voucher.pluck(:number)).to include(original.number)
  end

  it "keeps issuing from the top after a void, never backfilling the hole" do
    a = expense!("a", 1_000)
    b = expense!("b", 2_000)
    expect(voucher_for(b).number).to end_with("00002")

    a.update!(amount_cents: 1_500)

    expect(voucher_for(a).number).to end_with("00003")
    expect(Voucher.active.pluck(:number).sort).to eq([voucher_for(b).number, voucher_for(a).number].sort)
  end

  it "counts voided documents when numbering, so the sequence only grows" do
    e = expense!("x", 1_000)
    3.times { |i| e.update!(amount_cents: 1_000 + ((i + 1) * 100)) }

    numbers = Voucher.order(:number).pluck(:number)
    sequence = numbers.map { |n| n.split("-").last.to_i }

    expect(sequence).to eq((1..4).to_a)
    expect(Voucher.active.count).to eq(1)
    expect(Voucher.voided.count).to eq(3)
  end

  it "releases what a voided voucher had settled" do
    e = expense!("y", 5_000)
    original = voucher_for(e)

    e.update!(amount_cents: 6_000)

    expect(original.reload.payment_allocations).to be_empty
    expect(e.reload.settled_cents).to eq(6_000)
    expect(e.outstanding_cents).to eq(0)
    expect(cash.reload.balance_cents).to eq(894_000)
  end
end
