# frozen_string_literal: true

require "rails_helper"

RSpec.describe StorefrontListing, type: :model do
  let(:company) { create(:company, business_type: "distribution") }
  let(:category) { create(:ingredient_category, company: company) }

  before { Current.company = company }

  def ingredient(**attrs)
    create(:ingredient, company: company, ingredient_category: category, **attrs)
  end

  describe "slug" do
    it "is generated from the ingredient name, keeping Arabic letters" do
      listing = described_class.create!(ingredient: ingredient(name: "زيت زيتون بكر"))

      expect(listing.slug).to eq("زيت-زيتون-بكر")
    end

    it "prefers the website title and avoids collisions" do
      first = described_class.create!(ingredient: ingredient(name: "Kit A"), title: "Dental Kit")
      second = described_class.create!(ingredient: ingredient(name: "Kit B"), title: "Dental Kit")

      expect(first.slug).to eq("dental-kit")
      expect(second.slug).to eq("dental-kit-2")
    end

    it "is normalized when typed by hand" do
      listing = described_class.create!(ingredient: ingredient, slug: "My Product!!")

      expect(listing.slug).to eq("my-product")
    end
  end

  it "allows one listing per ingredient" do
    item = ingredient
    described_class.create!(ingredient: item)

    expect(described_class.new(ingredient: item)).not_to be_valid
  end

  it "rejects an ingredient from another company" do
    foreign = ingredient
    other = create(:company)
    Current.company = other

    listing = described_class.new(company: other, ingredient: foreign)
    expect(listing).not_to be_valid
    expect(listing.errors[:ingredient]).to be_present
  end

  describe ".visible" do
    it "excludes hidden listings and inactive products" do
      shown = described_class.create!(ingredient: ingredient)
      described_class.create!(ingredient: ingredient, published: false)
      described_class.create!(ingredient: ingredient(active: false))

      expect(described_class.visible).to contain_exactly(shown)
    end
  end

  it "falls back to the ingredient name and price" do
    listing = described_class.create!(ingredient: ingredient(name: "Gloves", selling_price_cents: 12_500))

    expect(listing.display_title).to eq("Gloves")
    expect(listing.price_cents).to eq(12_500)
    listing.update!(title: "Nitrile gloves")
    expect(listing.display_title).to eq("Nitrile gloves")
  end

  it "caps the number of photos" do
    listing = described_class.create!(ingredient: ingredient)
    listing.images = Array.new(StorefrontListing::MAX_IMAGES + 1) do |i|
      { io: File.open(Rails.root.join("spec/fixtures/files/storefront_product.png")), filename: "p#{i}.png", content_type: "image/png" }
    end

    expect(listing).not_to be_valid
    expect(listing.errors[:images]).to be_present
  end
end
