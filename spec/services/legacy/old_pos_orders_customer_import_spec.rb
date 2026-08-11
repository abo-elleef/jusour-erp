# frozen_string_literal: true

require "rails_helper"

RSpec.describe Legacy::OldPosOrdersCustomerImport do
  let(:company) { create(:company) }
  let(:path) { Rails.root.join("spec/fixtures/legacy/old_pos_orders_day.csv") }

  describe "#parse_candidates" do
    it "extracts named customers with Egyptian mobiles and skips walk-ins" do
      candidates = described_class.new(path: path, company: company).parse_candidates

      expect(candidates.map(&:name)).not_to include("العميل النقدي", "عميل طاولة")
      amira = candidates.find { |c| c.phone == "01068311550" }
      expect(amira.name).to eq("اميره المتولي")
      expect(amira.order_count).to eq(2)
      expect(amira.legacy_account_code).to eq("01/1/3/10894")

      from_name = candidates.find { |c| c.phone == "01094710914" }
      expect(from_name.name).to eq("محمد")
    end

    it "assigns synthetic emails for name-only customers when enabled" do
      candidates = described_class.new(
        path: path, company: company, include_name_only: true
      ).parse_candidates

      ehab = candidates.find { |c| c.name == "ايهاب الزلفي" }
      expect(ehab.phone).to be_nil
      expect(ehab.email).to eq("legacy-01-1-3-11986@import.invalid")
    end

    it "does not treat digit-soup account names as phones" do
      soup_path = Rails.root.join("tmp/legacy_digit_soup.csv")
      FileUtils.mkdir_p(soup_path.dirname)
      File.write(soup_path, <<~CSV)
        ,,ج . م,,عملاء- 589515891498561,,,,مخزن المطعم,,,,1,,1,,الفرع الرئيسي,,100,,0,,100,,ج . م,,100,, 100.00 ,,عملاء- 589515891498561,,01/1/3/6135,,x,,مخزن المطعم,,فاتورة,,2026/07/31
      CSV

      candidates = described_class.new(path: soup_path, company: company).parse_candidates
      expect(candidates.size).to eq(1)
      expect(candidates.first.phone).to be_nil
    end
  end

  describe "#call" do
    it "creates phone customers when APPLY mode is on" do
      result = described_class.new(path: path, company: company, dry_run: false).call

      expect(result.created.size).to eq(2)
      expect(Customer.unscoped.where(company_id: company.id).pluck(:phone)).to contain_exactly(
        "01068311550", "01094710914"
      )
    end

    it "is idempotent on phone" do
      described_class.new(path: path, company: company, dry_run: false).call
      result = described_class.new(path: path, company: company, dry_run: false).call

      expect(result.created).to be_empty
      expect(result.skipped_existing.size).to eq(2)
      expect(Customer.unscoped.where(company_id: company.id).count).to eq(2)
    end

    it "dry-run does not write" do
      expect do
        described_class.new(path: path, company: company, dry_run: true).call
      end.not_to change { Customer.unscoped.where(company_id: company.id).count }
    end
  end
end
