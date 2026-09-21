# frozen_string_literal: true

require "rails_helper"

RSpec.describe Inventory::UnitConversionReview do
  let(:company) { create(:company) }
  let(:category) { create(:ingredient_category, company: company) }

  before { Current.company = company }

  def unit(name)
    company.units.where("LOWER(name) = ?", name.downcase).first ||
      company.units.create!(name: name, active: true)
  end

  def conversion(base:, alt:, factor:, name: "Ingredient #{SecureRandom.hex(3)}")
    unit(base)
    ingredient = create(:ingredient, company: company, ingredient_category: category, name: name, unit: base)
    ingredient.ingredient_units.create!(unit: unit(alt), base_units_per_unit: factor, company: company)
  end

  def review(rows, peers: nil)
    described_class.new(Array(rows), peers: peers).rows.first
  end

  describe "units that are real measures" do
    it "vouches for a rate the units themselves give" do
      row = review(conversion(base: "kg", alt: "g", factor: 0.001))

      expect(row.status).to eq(:ok)
      expect(row.basis).to eq(:physical)
      expect(row.expected).to eq(0.001)
    end

    it "flags a rate that contradicts them" do
      row = review(conversion(base: "kg", alt: "g", factor: 430))

      expect(row.status).to eq(:check)
      expect(row.expected).to eq(0.001)
    end

    it "reads Arabic unit names as the measures they are" do
      row = review(conversion(base: "كيلو جرام", alt: "جرام", factor: 0.001))

      expect(row.status).to eq(:ok)
      expect(row.basis).to eq(:physical)
    end

    it "keeps kilograms and grams apart in a name that mentions both" do
      row = review(conversion(base: "جالون ٣ كيلو", alt: "كيلو جرام", factor: 0.33))

      expect(row.status).to eq(:ok)
      expect(row.expected.round(4)).to eq(0.3333)
    end

    it "says nothing about units of different dimensions" do
      row = review(conversion(base: "kg", alt: "liters", factor: 0.9))

      expect(row.status).to eq(:unverified)
      expect(row.expected).to be_nil
    end
  end

  describe "counts written into the unit names" do
    it "reads a pack count on the alternate unit" do
      row = review(conversion(base: "زجاجة", alt: "كرتونة * 12", factor: 12))

      expect(row.status).to eq(:ok)
      expect(row.expected).to eq(12)
    end

    it "divides one pack count by the other" do
      row = review(conversion(base: "كرتونة * 1000", alt: "عمود * 50", factor: 0.02))

      expect(row.status).to eq(:check)
      expect(row.expected).to eq(0.05)
    end

    it "reads Arabic-Indic digits" do
      row = review(conversion(base: "بلته * 1000", alt: "كيس * ٥٠", factor: 0.05))

      expect(row.status).to eq(:ok)
    end

    it "reads a count the alternate unit states in the base unit" do
      row = review(conversion(base: "قطعة", alt: "كيس دجاج ١٤ قطعة", factor: 14))

      expect(row.status).to eq(:ok)
      expect(row.expected).to eq(14)
    end

    it "reads the same count backwards when the base is the one that states it" do
      row = review(conversion(base: "كيس استربس متبل (٢٠ قطعة)", alt: "قطعة", factor: 0.05))

      expect(row.status).to eq(:ok)
      expect(row.expected.round(4)).to eq(0.05)
    end

    it "allows the rounding a name-stated size invites" do
      # 1/60 entered as 0.017 rather than 0.016667.
      row = review(conversion(base: "جمدانه ٦٠ كيلو", alt: "كيلو جرام", factor: 0.017))

      expect(row.status).to eq(:ok)
    end

    it "leaves a bare number in a name alone" do
      # "batch chicken 16" holds 112 pieces — the 16 is not a count of the base.
      row = review(conversion(base: "قطعة", alt: "باتش دجاج16", factor: 112))

      expect(row.status).to eq(:unverified)
    end

    it "does not read a packed count as a rate for a measure it cannot pack" do
      # A carton of ten 1kg packs really is 0.0001 cartons per gram.
      row = review(conversion(base: "كرتونة * 10", alt: "جرام", factor: 0.0001))

      expect(row.status).to eq(:unverified)
    end

    it "ignores a size a fraction word qualifies" do
      row = review(conversion(base: "كيس نص كيلو", alt: "جرام", factor: 0.002))

      expect(row.status).to eq(:unverified)
    end
  end

  describe "what other ingredients do with the same pair" do
    it "flags the odd one out when nothing else can judge the rate" do
      agreeing = [
        conversion(base: "كيس", alt: "كرتونة", factor: 1000),
        conversion(base: "كيس", alt: "كرتونة", factor: 1000)
      ]
      odd = conversion(base: "كيس", alt: "كرتونة", factor: 10)

      row = review(odd, peers: agreeing + [odd])

      expect(row.status).to eq(:check)
      expect(row.basis).to eq(:peer)
      expect(row.expected).to eq(1000)
      expect(row.peer_count).to eq(2)
    end

    it "keeps quiet when only one other ingredient uses the pair" do
      other = conversion(base: "كيس", alt: "كرتونة", factor: 1000)
      odd = conversion(base: "كيس", alt: "كرتونة", factor: 10)

      expect(review(odd, peers: [other, odd]).status).to eq(:unverified)
    end

    it "still sees peers that the page's own filters left out" do
      agreeing = Array.new(2) { conversion(base: "كيس", alt: "كرتونة", factor: 1000) }
      odd = conversion(base: "كيس", alt: "كرتونة", factor: 10)

      # Only the odd row is being displayed; the agreement comes from the peers.
      expect(review(odd, peers: agreeing + [odd]).status).to eq(:check)
    end
  end

  it "flags an alternate unit the same size as the base" do
    row = review(conversion(base: "قفص", alt: "كرتونة", factor: 1))

    expect(row.status).to eq(:check)
    expect(row.basis).to eq(:identity)
  end

  it "reports every row it was given" do
    rows = [
      conversion(base: "kg", alt: "g", factor: 0.001),
      conversion(base: "kg", alt: "g", factor: 430)
    ]
    review = described_class.new(rows)

    expect(review.rows.size).to eq(2)
    expect(review.checks.size).to eq(1)
  end
end
