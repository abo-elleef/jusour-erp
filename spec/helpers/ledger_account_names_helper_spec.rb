# frozen_string_literal: true

require "rails_helper"

# `account_name` on a journal line is a snapshot taken when the entry was
# written. For a treasury that is right — the name is data. For the accounts the
# app names itself it is not: those are translations, and a line posted from the
# English UI was showing "Accrued expenses" to an Arabic reader, sitting right
# next to a treasury rendered in Arabic.
RSpec.describe LedgerAccountNamesHelper, type: :helper do
  ACCRUED = Accounting::JournalEntryService::ACCRUED_EXPENSES_CODE
  RECEIVABLE = Accounting::JournalEntryService::OTHER_RECEIVABLES_CODE

  describe "a system account" do
    it "reads in the reader's locale, not the writer's" do
      english = I18n.with_locale(:en) { helper.ledger_account_name(ACCRUED, "Accrued expenses") }
      arabic  = I18n.with_locale(:ar) { helper.ledger_account_name(ACCRUED, "Accrued expenses") }

      expect(english).to eq("Accrued expenses")
      expect(arabic).to eq("مصروفات مستحقة")
      expect(arabic).not_to eq(english)
    end

    it "ignores a stored name written under the other locale" do
      # The row from the screenshot: posted in English, read in Arabic.
      arabic = I18n.with_locale(:ar) { helper.ledger_account_name(ACCRUED, "Accrued expenses") }
      expect(arabic).to eq("مصروفات مستحقة")
    end

    it "covers the receivable side too" do
      arabic = I18n.with_locale(:ar) { helper.ledger_account_name(RECEIVABLE, "Other receivables") }
      expect(arabic).to eq("أرصدة مدينة أخرى")
    end

    it "has a translation for every system account, in both locales" do
      Accounting::JournalEntryService::SYSTEM_ACCOUNT_NAME_KEYS.each do |code, key|
        %i[en ar].each do |locale|
          name = I18n.with_locale(locale) { helper.ledger_account_name(code, nil) }
          expect(name).not_to eq(code.to_s), "#{key} is missing in #{locale}"
          expect(name).to be_present
        end
      end
    end
  end

  describe "an account the user named" do
    it "keeps the stored name, which is data rather than a translation" do
      # A treasury code — renaming the safe should not rewrite old statements,
      # and translating it would be nonsense.
      expect(helper.ledger_account_name(1201, "الخزنة الرئيسية")).to eq("الخزنة الرئيسية")
      expect(helper.ledger_account_name(5007, "Rent")).to eq("Rent")
    end

    it "falls back to the code when nothing was stored" do
      expect(helper.ledger_account_name(5007, nil)).to eq("5007")
    end
  end

  describe "resolving straight from a journal line" do
    it "uses the line's own code and stored name" do
      line = JournalEntryLine.new(account_code: ACCRUED, account_name: "Accrued expenses")
      arabic = I18n.with_locale(:ar) { helper.ledger_line_account_name(line) }
      expect(arabic).to eq("مصروفات مستحقة")
    end
  end
end
