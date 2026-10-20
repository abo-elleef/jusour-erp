# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Public storefronts", type: :request do
  include ApplicationHelper

  let(:company) { create(:company, business_type: "distribution", slug: "acme-dental", name: "Acme Dental") }

  # Before the let! blocks below, so their records are built inside this tenant.
  before { Current.company = company }

  let(:category) { create(:ingredient_category, company: company, name: "Instruments") }
  let(:other_category) { create(:ingredient_category, company: company, name: "Consumables") }
  let!(:storefront) do
    Storefront.create!(company: company, enabled: true, subdomain: "acme", tagline: "Everything for your clinic",
      whatsapp_number: "+20 10 1234 5678")
  end
  let!(:mirror) do
    item = create(:ingredient, company: company, ingredient_category: category, name: "Mouth mirror", selling_price_cents: 4_500)
    StorefrontListing.create!(company: company, ingredient: item, description: "Stainless steel, autoclavable.")
  end
  let!(:gloves) do
    item = create(:ingredient, company: company, ingredient_category: other_category, name: "Nitrile gloves", selling_price_cents: 9_900)
    StorefrontListing.create!(company: company, ingredient: item, featured: true)
  end
  let!(:hidden) do
    item = create(:ingredient, company: company, ingredient_category: category, name: "Secret drill")
    StorefrontListing.create!(company: company, ingredient: item, published: false)
  end

  describe "by path" do
    it "shows published products without login" do
      get public_storefront_home_path(company_slug: company.slug)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Acme Dental", "Everything for your clinic", "Mouth mirror", "Nitrile gloves")
      expect(response.body).to include(format_money(4_500))
      expect(response.body).not_to include("Secret drill")
      expect(response.body).to include(public_storefront_product_path(company_slug: company.slug, listing_slug: mirror.slug))
    end

    it "filters by category and search" do
      get public_storefront_home_path(company_slug: company.slug, category: other_category.id)
      expect(response.body).to include("Nitrile gloves")
      expect(response.body).not_to include("Mouth mirror")

      get public_storefront_home_path(company_slug: company.slug, q: "mirror")
      expect(response.body).to include("Mouth mirror")
      expect(response.body).not_to include("Nitrile gloves")
    end

    it "shows a product page with a WhatsApp inquiry" do
      get public_storefront_product_path(company_slug: company.slug, listing_slug: mirror.slug)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Mouth mirror", "Stainless steel, autoclavable.", "https://wa.me/201012345678?text=")
    end

    it "hides prices when the company turns them off" do
      storefront.update!(show_prices: false)

      get public_storefront_home_path(company_slug: company.slug)

      expect(response.body).not_to include(format_money(4_500))
      expect(response.body).to include(I18n.t("public.storefront.price_on_request", locale: :en))
    end

    it "404s for a hidden product, a disabled site, or a company without the feature" do
      get public_storefront_product_path(company_slug: company.slug, listing_slug: hidden.slug)
      expect(response).to have_http_status(:not_found)

      storefront.update!(enabled: false)
      get public_storefront_home_path(company_slug: company.slug)
      expect(response).to have_http_status(:not_found)

      storefront.update!(enabled: true)
      company.update!(feature_overrides: { "storefront" => false })
      get public_storefront_home_path(company_slug: company.slug)
      expect(response).to have_http_status(:not_found)
    end

    it "never shows another company's products" do
      other = create(:company, business_type: "distribution")
      Current.company = other
      Storefront.create!(company: other, enabled: true)
      foreign_item = create(:ingredient, company: other, ingredient_category: create(:ingredient_category, company: other),
        name: "Foreign product")
      StorefrontListing.create!(company: other, ingredient: foreign_item, slug: mirror.slug)
      Current.company = company

      get public_storefront_home_path(company_slug: company.slug)
      expect(response.body).not_to include("Foreign product")

      get public_storefront_product_path(company_slug: other.slug, listing_slug: mirror.slug)
      expect(response.body).to include("Foreign product")
      expect(response.body).not_to include("Mouth mirror")
    end

    it "serves a sitemap of the published products" do
      get public_storefront_sitemap_path(company_slug: company.slug)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/xml")
      expect(response.body).to include(public_storefront_product_url(company_slug: company.slug, listing_slug: mirror.slug))
      expect(response.body).not_to include(hidden.slug)
    end
  end

  describe "on the storefront's subdomain" do
    before { host! "acme.localhost" }

    it "serves the catalog at the root with host-relative links" do
      get "/"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Mouth mirror")
      expect(response.body).to include(%(href="/p/#{mirror.slug}"))
      expect(response.body).not_to include("/s/acme-dental")
    end

    it "serves product pages" do
      get "/p/#{ERB::Util.url_encode(gloves.slug)}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Nitrile gloves")
    end

    it "404s for an unknown subdomain" do
      host! "nobody.localhost"
      get "/"

      expect(response).to have_http_status(:not_found)
    end

    it "does not expose the app's own pages under the client's brand" do
      get "/users/sign_in"
      expect(response).to have_http_status(:not_found)

      get "/admin"
      expect(response).to have_http_status(:not_found)
    end
  end
end
