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

  describe "look and feel" do
    it "renders the brand colors and font from settings" do
      storefront.update!(primary_color: "#1d4ed8", accent_color: "#0f172a", font: "cairo", header_style: "dark")

      get public_storefront_home_path(company_slug: company.slug)

      expect(response.body).to include("--sf-primary: #1d4ed8", "--sf-on-primary: #ffffff", "--sf-accent: #0f172a")
      expect(response.body).to include("fonts.googleapis.com/css2?family=Cairo")
      expect(response.body).to include("bg-(--sf-accent) text-(--sf-on-accent)")
    end

    it "never writes an unvalidated color into the page" do
      storefront.update_columns(primary_color: "red;}</style><script>alert(1)</script>")

      get public_storefront_home_path(company_slug: company.slug)

      expect(response.body).not_to include("<script>alert(1)")
      expect(response.body).to include("--sf-primary: #b45309")
    end

    it "shows the announcement bar and social links" do
      storefront.update!(announcement_enabled: true, announcement_text: "Free delivery this week", announcement_url: "/?q=gloves",
        instagram_url: "instagram.com/acme")

      get public_storefront_home_path(company_slug: company.slug)

      expect(response.body).to include("Free delivery this week", %(href="/?q=gloves"), "https://instagram.com/acme")
    end

    it "serves Arabic copy to Arabic visitors" do
      storefront.update!(tagline_ar: "كل ما تحتاجه عيادتك")
      mirror.update!(title_ar: "مرآة فم")
      StorefrontCategory.create!(company: company, ingredient_category: category, title_ar: "أدوات", description_ar: "أدوات الفحص")

      get public_storefront_home_path(company_slug: company.slug, locale: "ar")
      expect(response.body).to include("كل ما تحتاجه عيادتك", "مرآة فم", "أدوات")

      get public_storefront_home_path(company_slug: company.slug, category: category.id, locale: "ar")
      expect(response.body).to include("أدوات الفحص")

      get public_storefront_home_path(company_slug: company.slug, locale: "en")
      expect(response.body).to include("Everything for your clinic", "Mouth mirror", "Instruments")
    end

    it "finds products by their Arabic title" do
      mirror.update!(title_ar: "مرآة فم")

      get public_storefront_home_path(company_slug: company.slug, q: "مرآة")

      expect(response.body).to include("Mouth mirror")
      expect(response.body).not_to include("Nitrile gloves")
    end

    it "shows a shop-by-category grid on the home page" do
      StorefrontCategory.create!(company: company, ingredient_category: other_category, title: "Gloves & masks")

      get public_storefront_home_path(company_slug: company.slug)

      expect(response.body).to include(I18n.t("public.storefront.shop_by_category", locale: :en), "Gloves &amp; masks")
    end
  end

  describe "home page sections" do
    def add(type, position, **settings)
      StorefrontSection.new(storefront: storefront, section_type: type, position: position).tap do |s|
        s.assign_settings(settings)
        s.save!
      end
    end

    it "renders the saved blocks in order and skips hidden ones" do
      add("promo_banner", 0, title: "Winter offer", button_label: "Shop now", link: "/?q=gloves")
      add("category_products", 1, category_id: other_category.id, title: "Consumables row")
      add("text_image", 2, title: "Our story", body: "Founded in Cairo").update!(enabled: false)

      get public_storefront_home_path(company_slug: company.slug)

      body = response.body
      expect(body).to include("Winter offer", %(href="/?q=gloves"), "Consumables row", "Nitrile gloves")
      expect(body.index("Winter offer")).to be < body.index("Consumables row")
      expect(body).not_to include("Our story", I18n.t("public.storefront.chat_on_whatsapp", locale: :en))
    end

    it "shows the default layout before any block is saved" do
      get public_storefront_home_path(company_slug: company.slug)

      expect(response.body).to include("Everything for your clinic", "Mouth mirror", I18n.t("public.storefront.featured", locale: :en))
    end

    it "shows plain results, without the blocks, for search and later pages" do
      add("promo_banner", 0, title: "Winter offer")

      get public_storefront_home_path(company_slug: company.slug, q: "mirror")
      expect(response.body).to include("Mouth mirror")
      expect(response.body).not_to include("Winter offer")
    end
  end

  describe "info pages" do
    let!(:delivery) do
      storefront.pages.create!(slot: "delivery_returns", enabled: true,
        body: %(<h2>Shipping</h2><p>We deliver across Egypt.</p><script>alert("x")</script><a href="javascript:alert(1)">bad</a>))
    end

    it "shows a published page, sanitized, and links it from the footer" do
      get public_storefront_page_path(company_slug: company.slug, page_slot: "delivery-returns")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Delivery &amp; returns", "We deliver across Egypt.")
      expect(response.body).not_to include("<script>alert", "javascript:alert")

      get public_storefront_home_path(company_slug: company.slug)
      expect(response.body).to include(public_storefront_page_path(company_slug: company.slug, page_slot: "delivery-returns"))
    end

    it "404s for unpublished, empty or unknown pages" do
      storefront.pages.create!(slot: "privacy", enabled: true)
      delivery.update!(enabled: false)

      %w[delivery-returns privacy blog].each do |slot|
        get public_storefront_page_path(company_slug: company.slug, page_slot: slot)
        expect(response).to have_http_status(:not_found), "expected /pages/#{slot} to 404"
      end
    end

    it "teases the About us page on the home page, only once it's published" do
      about = storefront.pages.create!(slot: "about", enabled: false, body: "<p>Founded in Cairo to serve clinics.</p>")
      StorefrontSection.create!(storefront: storefront, section_type: "about", position: 0)

      get public_storefront_home_path(company_slug: company.slug)
      expect(response.body).not_to include("Founded in Cairo")

      about.update!(enabled: true)
      get public_storefront_home_path(company_slug: company.slug)
      expect(response.body).to include("Founded in Cairo", I18n.t("public.storefront.read_more", locale: :en),
        public_storefront_page_path(company_slug: company.slug, page_slot: "about"))
    end

    it "shows the tagline and contact details, not the company story, in the footer" do
      storefront.update!(map_url: "https://maps.app.goo.gl/acme")

      get public_storefront_home_path(company_slug: company.slug)

      footer = response.body[response.body.index("<footer")..]
      expect(footer).to include("Everything for your clinic", "https://maps.app.goo.gl/acme", "+20 10 1234 5678")
    end

    it "adds the contact details under the contact page" do
      storefront.pages.create!(slot: "contact", enabled: true, body: "<p>Open Saturday to Thursday</p>")

      get public_storefront_page_path(company_slug: company.slug, page_slot: "contact")

      expect(response.body).to include("Open Saturday to Thursday", "https://wa.me/201012345678")

      storefront.update!(map_url: "https://maps.app.goo.gl/acme")
      get public_storefront_page_path(company_slug: company.slug, page_slot: "contact")
      expect(response.body).to include("https://maps.app.goo.gl/acme")
    end

    it "serves pages on the subdomain and lists them in the sitemap" do
      host! "acme.localhost"

      get "/pages/delivery-returns"
      expect(response).to have_http_status(:ok)

      get "/sitemap.xml"
      expect(response.body).to include("http://acme.localhost/pages/delivery-returns")
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
