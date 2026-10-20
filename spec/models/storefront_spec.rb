# frozen_string_literal: true

require "rails_helper"

RSpec.describe Storefront, type: :model do
  let(:company) { create(:company, business_type: "distribution") }

  before { Current.company = company }

  describe ".subdomain_from_host" do
    around do |example|
      original = Rails.configuration.x.storefront_domain
      Rails.configuration.x.storefront_domain = "saqr.store"
      example.run
    ensure
      Rails.configuration.x.storefront_domain = original
    end

    it "returns the single label in front of the storefront domain" do
      expect(described_class.subdomain_from_host("acme.saqr.store")).to eq("acme")
      expect(described_class.subdomain_from_host("ACME.Saqr.Store")).to eq("acme")
    end

    it "ignores the bare domain, nested labels, reserved labels and other hosts" do
      expect(described_class.subdomain_from_host("saqr.store")).to be_nil
      expect(described_class.subdomain_from_host("a.b.saqr.store")).to be_nil
      expect(described_class.subdomain_from_host("www.saqr.store")).to be_nil
      expect(described_class.subdomain_from_host("app.saqr.store")).to be_nil
      expect(described_class.subdomain_from_host("acme.example.com")).to be_nil
      expect(described_class.subdomain_from_host("evilsaqr.store")).to be_nil
    end

    it "is off entirely when no storefront domain is configured" do
      Rails.configuration.x.storefront_domain = ""

      expect(described_class.subdomain_from_host("acme.saqr.store")).to be_nil
    end
  end

  describe "subdomain" do
    it "is normalized to lowercase and blank becomes nil" do
      storefront = described_class.create!(subdomain: "  Acme-Foods ")
      expect(storefront.subdomain).to eq("acme-foods")

      storefront.update!(subdomain: "")
      expect(storefront.subdomain).to be_nil
    end

    it "rejects bad formats and reserved names" do
      %w[-acme acme- acme_foods acme.foods].each do |bad|
        expect(described_class.new(subdomain: bad)).not_to be_valid, "expected #{bad} to be invalid"
      end
      expect(described_class.new(subdomain: "www")).not_to be_valid
    end

    it "is unique across companies, ignoring case" do
      described_class.create!(subdomain: "acme")
      other = create(:company)
      Current.company = other

      dupe = described_class.new(subdomain: "ACME")
      expect(dupe).not_to be_valid
      expect(dupe.errors[:subdomain]).to be_present
    end
  end

  describe ".enabled_for_subdomain" do
    it "finds an enabled storefront of an active company regardless of the current tenant" do
      storefront = described_class.create!(subdomain: "acme", enabled: true)
      Current.company = create(:company)

      expect(described_class.enabled_for_subdomain("acme")).to eq(storefront)
    end

    it "skips disabled storefronts and inactive companies" do
      storefront = described_class.create!(subdomain: "acme", enabled: false)
      expect(described_class.enabled_for_subdomain("acme")).to be_nil

      storefront.update!(enabled: true)
      company.update!(active: false)
      expect(described_class.enabled_for_subdomain("acme")).to be_nil
    end
  end

  it "rejects non-image uploads" do
    storefront = described_class.new
    storefront.logo.attach(io: StringIO.new("text"), filename: "logo.txt", content_type: "text/plain")

    expect(storefront).not_to be_valid
    expect(storefront.errors[:logo]).to be_present
  end

  it "is off for restaurants and on for distributors by default" do
    expect(build(:company, business_type: "restaurant").feature_enabled?(:storefront)).to be(false)
    expect(build(:company, business_type: "distribution").feature_enabled?(:storefront)).to be(true)
  end
end
