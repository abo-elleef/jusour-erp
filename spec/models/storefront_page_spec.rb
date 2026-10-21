# frozen_string_literal: true

require "rails_helper"

RSpec.describe StorefrontPage, type: :model do
  let(:company) { create(:company, business_type: "distribution") }
  let(:storefront) { Storefront.create!(company: company) }

  before { Current.company = company }

  it "only exists in the four fixed slots, once each" do
    expect(storefront.pages.new(slot: "blog")).not_to be_valid

    storefront.pages.create!(slot: "about")
    expect(storefront.pages.new(slot: "about")).not_to be_valid
  end

  it "maps slots to URL names and back, refusing anything else" do
    expect(described_class.new(slot: "delivery_returns").to_param_slot).to eq("delivery-returns")
    expect(described_class.slot_from_param("delivery-returns")).to eq("delivery_returns")
    expect(described_class.slot_from_param("../../etc")).to be_nil
  end

  it "serves each language its own body and falls back to the other" do
    page = storefront.pages.create!(slot: "about", enabled: true, body: "<p>English story</p>")

    expect(page.display_body(locale: :ar).to_plain_text).to eq("English story")
    page.update!(body_ar: "<p>قصتنا</p>")
    expect(page.display_body(locale: :ar).to_plain_text).to eq("قصتنا")
    expect(page.display_body(locale: :en).to_plain_text).to eq("English story")
  end

  it "uses the standard title unless one is set" do
    page = storefront.pages.new(slot: "privacy")

    expect(page.display_title(locale: :en)).to eq("Privacy policy")
    page.title_ar = "خصوصيتك"
    expect(page.display_title(locale: :ar)).to eq("خصوصيتك")
  end

  it "is live only when published and not empty" do
    page = storefront.pages.create!(slot: "contact", enabled: true, body: "<p> </p>")
    expect(page).not_to be_live

    page.update!(body: "<p>Open 9–5</p>")
    expect(page).to be_live
    page.update!(enabled: false)
    expect(page).not_to be_live
  end
end
