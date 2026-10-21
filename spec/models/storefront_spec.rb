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

  describe "look and feel" do
    it "accepts a dark brand color and rejects one too light to read on white" do
      expect(described_class.new(primary_color: "#1D4ED8")).to be_valid
      expect(described_class.new(primary_color: "#1D4ED8").tap(&:valid?).primary_color).to eq("#1d4ed8")

      light = described_class.new(primary_color: "#facc15")
      expect(light).not_to be_valid
      expect(light.errors.details[:primary_color]).to include(error: :too_light)
    end

    it "only takes real hex colors, a listed font and a known header style" do
      expect(described_class.new(accent_color: "red; background:url(x)")).not_to be_valid
      expect(described_class.new(font: "Comic Sans")).not_to be_valid
      expect(described_class.new(header_style: "neon")).not_to be_valid
    end

    it "picks white or near-black text, whichever reads better" do
      expect(described_class.text_color_on("#1d4ed8")).to eq("#ffffff")
      expect(described_class.text_color_on("#fde68a")).to eq("#111827")
    end

    it "builds a Google Fonts link only for a non-system font" do
      expect(described_class.new(font: "system").google_fonts_url).to be_nil
      expect(described_class.new(font: "ibm_plex_sans_arabic").google_fonts_url).to include("family=IBM+Plex+Sans+Arabic")
    end
  end

  describe "social links" do
    it "adds https:// and keeps links that point at their network" do
      storefront = described_class.new(instagram_url: "instagram.com/curelix", youtube_url: "https://www.youtube.com/@curelix")

      expect(storefront).to be_valid
      expect(storefront.instagram_url).to eq("https://instagram.com/curelix")
      expect(storefront.social_links.map(&:first)).to eq(%w[instagram youtube])
    end

    it "rejects a link to some other site" do
      storefront = described_class.new(facebook_url: "https://evil.example/facebook.com")

      expect(storefront).not_to be_valid
      expect(storefront.errors.details[:facebook_url]).to include(error: :wrong_network)
    end
  end

  describe "announcement bar" do
    it "accepts https links and site paths, nothing else" do
      expect(described_class.new(announcement_url: "https://example.com/offer")).to be_valid
      expect(described_class.new(announcement_url: "/?category=1")).to be_valid
      expect(described_class.new(announcement_url: "javascript:alert(1)")).not_to be_valid
      expect(described_class.new(announcement_url: "//evil.example")).not_to be_valid
    end

    it "shows only when switched on and there is text in some language" do
      storefront = described_class.new(announcement_enabled: true, announcement_text_ar: "خصم ١٠٪")

      expect(storefront.announcement_visible?).to be(true)
      expect(storefront.localized(:announcement_text, locale: :en)).to eq("خصم ١٠٪")
      storefront.announcement_enabled = false
      expect(storefront.announcement_visible?).to be(false)
    end
  end

  it "serves each language its own copy and falls back to the other" do
    storefront = described_class.new(tagline: "Clinic supplies", tagline_ar: "مستلزمات العيادات", about: "English only")

    expect(storefront.localized(:tagline, locale: :en)).to eq("Clinic supplies")
    expect(storefront.localized(:tagline, locale: :ar)).to eq("مستلزمات العيادات")
    expect(storefront.localized(:about, locale: :ar)).to eq("English only")
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
