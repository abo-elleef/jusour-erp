# frozen_string_literal: true

require "rails_helper"

RSpec.describe JournalEntry, type: :model do
  let(:company_a) { create(:company) }
  let(:company_b) { create(:company) }

  def build_entry(company, number)
    user = create(:user, company: company)
    JournalEntry.new(
      company: company, created_by: user, entry_number: number,
      date: Date.current, description: "Test", entry_type: "auto",
      lines_attributes: [
        { account_code: 1150, account_name: "AR", account_type: "asset", debit_cents: 1_000, credit_cents: 0 },
        { account_code: 4001, account_name: "Sales", account_type: "revenue", debit_cents: 0, credit_cents: 1_000 }
      ]
    )
  end

  describe "entry numbers are per company" do
    # Regression: numbers are generated per company, but uniqueness used to be
    # global — so a second tenant reusing its own sequence collided and every
    # ledger-posting action (e.g. confirming a sales invoice) failed to save.
    it "lets two companies hold the same entry number" do
      Current.company = company_a
      expect(build_entry(company_a, "JE-2026-00001").save).to be(true)

      Current.company = company_b
      entry_b = build_entry(company_b, "JE-2026-00001")
      expect(entry_b.save).to be(true), entry_b.errors.full_messages.to_sentence
    end

    it "still rejects a duplicate number within the same company" do
      Current.company = company_a
      build_entry(company_a, "JE-2026-00007").save!

      dup = build_entry(company_a, "JE-2026-00007")
      expect(dup).not_to be_valid
      expect(dup.errors[:entry_number]).to be_present
    end

    it ".next_entry_number continues each company's own sequence" do
      Current.company = company_a
      build_entry(company_a, "JE-#{Date.current.year}-00001").save!
      expect(described_class.next_entry_number(company_a.id)).to eq("JE-#{Date.current.year}-00002")

      # Company B is unaffected by A's sequence.
      Current.company = company_b
      expect(described_class.next_entry_number(company_b.id)).to eq("JE-#{Date.current.year}-00001")
    end
  end
end
