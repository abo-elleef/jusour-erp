# frozen_string_literal: true

require "rails_helper"

RSpec.describe StorefrontSection, type: :model do
  let(:company) { create(:company, business_type: "distribution") }
  let(:storefront) { Storefront.create!(company: company) }

  before { Current.company = company }

  def section(type, **settings)
    described_class.new(storefront: storefront, section_type: type).tap { |s| s.assign_settings(settings) }
  end

  it "keeps only the settings its block declares, cast to their kind" do
    hero = section("hero", headline: "  Hello ", headline_ar: "مرحبا", show_contact_buttons: "0", evil: "<script>")

    expect(hero.settings).to eq("headline" => "Hello", "headline_ar" => "مرحبا", "show_contact_buttons" => false)
    expect(hero.text(:headline, locale: :ar)).to eq("مرحبا")
  end

  it "falls back to declared defaults" do
    expect(section("featured_products").setting(:limit)).to eq(8)
    expect(section("hero").setting(:show_contact_buttons)).to be(true)
  end

  it "accepts only safe button links and Google Maps map links" do
    expect(section("promo_banner", link: "/?category=1")).to be_valid
    expect(section("promo_banner", link: "javascript:alert(1)")).not_to be_valid
    expect(section("contact", map_url: "https://maps.app.goo.gl/abc")).to be_valid
    expect(section("contact", map_url: "https://evil.example/maps")).not_to be_valid
  end

  it "requires a category of the same company for a category block" do
    expect(section("category_products")).not_to be_valid

    own = create(:ingredient_category, company: company)
    expect(section("category_products", category_id: own.id)).to be_valid
  end

  it "rejects a product count that isn't offered" do
    expect(section("featured_products", limit: "500")).not_to be_valid
  end

  it "allows the all-products grid only once" do
    section("all_products").save!

    dupe = section("all_products")
    expect(dupe).not_to be_valid
    expect(dupe.errors.details[:section_type]).to include(error: :only_one)
  end

  it "caps the number of blocks" do
    StorefrontSection::MAX_SECTIONS.times { |i| section("about").tap { |s| s.position = i }.save! }

    expect(section("about")).not_to be_valid
  end

  describe "default layout" do
    it "is what the home page renders until the admin saves blocks" do
      expect(storefront.home_sections.map(&:section_type)).to eq(StorefrontSection::DEFAULT_LAYOUT)
      expect(storefront.sections).to be_empty
    end

    it "is saved once, then only enabled blocks render, in order" do
      described_class.seed_defaults!(storefront)
      described_class.seed_defaults!(storefront)
      expect(storefront.sections.count).to eq(StorefrontSection::DEFAULT_LAYOUT.size)

      storefront.sections.find_by(section_type: "about").update!(enabled: false)
      expect(storefront.home_sections.map(&:section_type)).to eq(%w[hero categories featured_products all_products])
    end
  end
end
