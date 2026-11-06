# frozen_string_literal: true

require "rails_helper"

RSpec.describe Printing::ReceiptLogo do
  let(:company) { create(:company) }
  let(:branch) { create(:location, company: company) }
  let(:other_branch) { create(:location, company: company) }
  let(:png) { Rails.root.join("spec/fixtures/files/storefront_product.png") }

  def attach(record, name)
    record.receipt_logo.attach(io: File.open(png), filename: name, content_type: "image/png")
    record.save!
  end

  before { Current.company = company }

  def company_setting
    CompanySetting.where(company: company).first_or_create!
  end

  def source_filename(location)
    described_class.with_source(location: location, company: company.reload) { |src| src && File.basename(src) }
  end

  it "yields nothing when no logo is configured anywhere" do
    expect(source_filename(branch)).to be_nil
  end

  it "uses the company logo when the branch has none" do
    attach(company_setting, "company.png")

    expect(source_filename(branch)).to end_with(".png")
    expect(described_class.attachment_for(location: branch, company: company.reload).filename.to_s).to eq("company.png")
  end

  it "prefers the branch's own logo over the company's" do
    attach(company_setting, "company.png")
    attach(branch, "branch.png")

    expect(described_class.attachment_for(location: branch, company: company.reload).filename.to_s).to eq("branch.png")
    expect(described_class.attachment_for(location: other_branch, company: company.reload).filename.to_s).to eq("company.png")
  end

  it "falls back to the legacy URL setting when nothing is uploaded" do
    company_setting.update!(receipt_logo_url: "https://example.com/logo.png")

    expect(described_class.with_source(location: branch, company: company.reload) { |src| src }).to eq("https://example.com/logo.png")
  end

  it "still yields the legacy fallback when the uploaded file is gone from storage" do
    attach(company_setting, "company.png")
    company_setting.update!(receipt_logo_url: "https://example.com/logo.png")
    company_setting.receipt_logo.blob.service.delete(company_setting.receipt_logo.blob.key)

    expect(described_class.with_source(location: branch, company: company.reload) { |src| src }).to eq("https://example.com/logo.png")
  end

  describe "validation" do
    it "rejects non-image uploads" do
      branch.receipt_logo.attach(io: StringIO.new("hi"), filename: "x.txt", content_type: "text/plain")

      expect(branch).not_to be_valid
      expect(branch.errors[:receipt_logo]).to be_present
    end

    it "rejects SVG" do
      branch.receipt_logo.attach(io: StringIO.new("<svg/>"), filename: "x.svg", content_type: "image/svg+xml")

      expect(branch).not_to be_valid
    end
  end
end
