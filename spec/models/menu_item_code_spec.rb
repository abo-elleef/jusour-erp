# frozen_string_literal: true

require "rails_helper"

RSpec.describe MenuItem, type: :model do
  # Factory category name "Category N" → code like "CATE".
  let(:category) { create(:category) }

  def item(attrs = {})
    create(:menu_item, { category: category }.merge(attrs))
  end

  describe "reference code" do
    it "auto-assigns a <CATEGORY_CODE>-NNN code, sequential within the category" do
      a = item
      b = item
      expect(a.code).to eq("#{category.code}-001")
      expect(b.code).to eq("#{category.code}-002")
    end

    it "numbers sequences independently per category" do
      other = create(:category)
      first_here = item
      first_there = create(:menu_item, category: other)
      expect(first_here.code).to eq("#{category.code}-001")
      expect(first_there.code).to eq("#{other.code}-001")
    end

    it "keeps a manager-provided custom code and skips it in the auto sequence" do
      custom = item(code: "SPECIAL-9")
      expect(custom.code).to eq("SPECIAL-9")
      expect(item.code).to eq("#{category.code}-001")
    end

    it "rejects a duplicate code within the company (case-insensitive)" do
      item(code: "DUP-1")
      dup = build(:menu_item, category: category, code: "dup-1")
      expect(dup).not_to be_valid
      expect(dup.errors[:code]).to be_present
    end

    it "lets the code be edited after creation" do
      mi = item
      mi.update!(code: "DRINK-9")
      expect(mi.reload.code).to eq("DRINK-9")
    end
  end
end
