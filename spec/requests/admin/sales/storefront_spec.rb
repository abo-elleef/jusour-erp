# frozen_string_literal: true

require "rails_helper"

# users.wages_account_code is NOT NULL in schema.rb with nothing in the app that
# sets it (the same pre-existing bug the leads specs skip on). Setting it here
# keeps these specs running instead of skipping them; drop the helper once the
# column is fixed.
RSpec.describe "Admin storefront", type: :request do
  include Devise::Test::IntegrationHelpers

  def staff(*traits, company:)
    @wages_codes = (@wages_codes || 2500) + 1
    create(:user, *traits, company: company, wages_account_code: @wages_codes)
  end

  let(:company) { create(:company, business_type: "distribution") }

  before { Current.company = company }

  let(:owner) { staff(:owner, company: company) }
  let(:category) { create(:ingredient_category, company: company, name: "Instruments") }
  let(:photo) { fixture_file_upload("storefront_product.png", "image/png") }

  def ingredient(**attrs)
    create(:ingredient, company: company, ingredient_category: category, **attrs)
  end

  describe "access" do
    it "is hidden from companies without the feature" do
      restaurant = create(:company, business_type: "restaurant")
      Current.company = restaurant
      sign_in staff(:owner, company: restaurant)

      get admin_sales_storefront_path

      expect(response).to redirect_to(admin_root_path)
    end

    it "needs the storefront:manage permission" do
      manager = staff(:manager, company: company)
      manager.effective_role.update!(permissions: manager.effective_role.permissions - ["storefront:manage"])
      sign_in manager

      get admin_sales_storefront_listings_path

      expect(response).to redirect_to(admin_root_path)
    end
  end

  describe "settings" do
    before { sign_in owner }

    it "creates the storefront on first save" do
      get admin_sales_storefront_path
      expect(response).to have_http_status(:ok)

      patch admin_sales_storefront_path, params: {
        storefront: { enabled: "1", subdomain: "Acme", tagline: "Clinic supplies", whatsapp_number: "+201012345678", logo: photo }
      }

      expect(response).to redirect_to(admin_sales_storefront_path)
      storefront = Storefront.sole
      expect(storefront).to have_attributes(enabled: true, subdomain: "acme", tagline: "Clinic supplies")
      expect(storefront.logo).to be_attached
    end

    it "saves the look and feel, announcement, social links and Arabic copy" do
      patch admin_sales_storefront_path, params: {
        storefront: { primary_color: "#1D4ED8", accent_color: "#0f172a", font: "tajawal", header_style: "dark",
                      announcement_enabled: "1", announcement_text: "Offer", announcement_text_ar: "عرض",
                      tiktok_url: "tiktok.com/@acme", tagline_ar: "شعار", map_url: "https://maps.app.goo.gl/acme" }
      }

      expect(response).to redirect_to(admin_sales_storefront_path)
      expect(Storefront.sole).to have_attributes(primary_color: "#1d4ed8", font: "tajawal", header_style: "dark",
        announcement_enabled: true, announcement_text_ar: "عرض", tiktok_url: "https://tiktok.com/@acme", tagline_ar: "شعار",
        map_url: "https://maps.app.goo.gl/acme")
    end

    it "refuses a brand color that can't be read on white" do
      patch admin_sales_storefront_path, params: { storefront: { primary_color: "#fef08a" } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include(I18n.t("activerecord.errors.models.storefront.attributes.primary_color.too_light"))
    end

    it "re-renders with an error for a taken subdomain" do
      other = create(:company)
      Storefront.create!(company: other, subdomain: "acme")

      patch admin_sales_storefront_path, params: { storefront: { subdomain: "acme" } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(Storefront.where(company: company)).to be_empty
    end

    it "removes the logo when asked" do
      storefront = Storefront.create!(company: company)
      storefront.logo.attach(photo)

      patch admin_sales_storefront_path, params: { storefront: { tagline: "x", remove_logo: "1" } }

      expect(storefront.reload.logo).not_to be_attached
    end
  end

  describe "listings" do
    before { sign_in owner }

    it "adds a single product with photos" do
      item = ingredient(name: "Mouth mirror")

      get new_admin_sales_storefront_listing_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Mouth mirror")

      post admin_sales_storefront_listings_path, params: {
        storefront_listing: { ingredient_id: item.id, title: "Mirror #4", description: "Steel", images: [photo] }
      }

      listing = StorefrontListing.sole
      expect(response).to redirect_to(edit_admin_sales_storefront_listing_path(listing))
      expect(listing).to have_attributes(ingredient: item, title: "Mirror #4", slug: "mirror-4", published: true)
      expect(listing.images.count).to eq(1)
    end

    it "keeps existing photos when more are uploaded" do
      listing = StorefrontListing.create!(ingredient: ingredient)
      listing.images.attach(photo)

      patch admin_sales_storefront_listing_path(listing),
        params: { storefront_listing: { featured: "1", images: [fixture_file_upload("storefront_product.png", "image/png")] } }

      expect(listing.reload.images.count).to eq(2)
      expect(listing).to be_featured
    end

    it "rejects a non-image upload" do
      listing = StorefrontListing.create!(ingredient: ingredient)

      patch admin_sales_storefront_listing_path(listing),
        params: { storefront_listing: { images: [fixture_file_upload("not_an_image.txt", "text/plain")] } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(listing.reload.images).not_to be_attached
    end

    it "removes one photo" do
      listing = StorefrontListing.create!(ingredient: ingredient)
      listing.images.attach(photo)
      attachment = listing.images.first

      delete remove_image_admin_sales_storefront_listing_path(listing, attachment_id: attachment.id)

      expect(response).to redirect_to(edit_admin_sales_storefront_listing_path(listing))
      expect(listing.reload.images).not_to be_attached
    end

    it "publishes many products at once, skipping ones already listed" do
      listed = ingredient(name: "Already listed")
      StorefrontListing.create!(ingredient: listed)
      new_items = [ingredient(name: "Gloves"), ingredient(name: "Masks")]

      get bulk_new_admin_sales_storefront_listings_path
      expect(response.body).to include("Gloves", "Masks")
      expect(response.body).not_to include("Already listed")

      post bulk_create_admin_sales_storefront_listings_path, params: { ingredient_ids: (new_items + [listed]).map(&:id) }

      expect(response).to redirect_to(admin_sales_storefront_listings_path)
      expect(StorefrontListing.count).to eq(3)
      expect(StorefrontListing.where(ingredient: listed).count).to eq(1)
    end

    it "lists, filters and sorts" do
      StorefrontListing.create!(ingredient: ingredient(name: "Zinc paste", selling_price_cents: 100))
      StorefrontListing.create!(ingredient: ingredient(name: "Amalgam", selling_price_cents: 900), published: false)

      get admin_sales_storefront_listings_path(sort: "price", dir: "desc")
      expect(response).to have_http_status(:ok)
      expect(response.body.index("Amalgam")).to be < response.body.index("Zinc paste")

      get admin_sales_storefront_listings_path(status: "hidden")
      expect(response.body).to include("Amalgam")
      expect(response.body).not_to include("Zinc paste")

      get admin_sales_storefront_listings_path(q: "zinc")
      expect(response.body).to include("Zinc paste")
      expect(response.body).not_to include("Amalgam")
    end

    it "removes a product from the website without touching the inventory item" do
      item = ingredient
      listing = StorefrontListing.create!(ingredient: item)

      delete admin_sales_storefront_listing_path(listing)

      expect(StorefrontListing.count).to eq(0)
      expect(Ingredient.exists?(item.id)).to be(true)
    end
  end

  describe "website categories" do
    before { sign_in owner }

    it "lists active categories and saves a photo and names on first edit" do
      category
      get admin_sales_storefront_categories_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Instruments")

      get edit_admin_sales_storefront_category_path(category)
      expect(response).to have_http_status(:ok)

      patch admin_sales_storefront_category_path(category), params: {
        storefront_category: { title: "Dental instruments", title_ar: "أدوات الأسنان", image: photo }
      }

      expect(response).to redirect_to(admin_sales_storefront_categories_path)
      meta = StorefrontCategory.sole
      expect(meta).to have_attributes(ingredient_category: category, title: "Dental instruments", title_ar: "أدوات الأسنان")
      expect(meta.image).to be_attached
    end

    it "removes the photo when asked" do
      meta = StorefrontCategory.create!(ingredient_category: category)
      meta.image.attach(photo)

      patch admin_sales_storefront_category_path(category), params: { storefront_category: { title: "", remove_image: "1" } }

      expect(meta.reload.image).not_to be_attached
    end
  end

  describe "home page editor" do
    let!(:storefront) { Storefront.create!(company: company, enabled: true) }

    before { sign_in owner }

    it "starts from the default layout" do
      get admin_sales_storefront_sections_path

      expect(response).to have_http_status(:ok)
      expect(storefront.sections.pluck(:section_type)).to eq(StorefrontSection::DEFAULT_LAYOUT)
      expect(response.body).to include(I18n.t("sales.storefront_sections.types.hero.name"))
    end

    it "adds a block and saves its settings, photo and Arabic text" do
      get admin_sales_storefront_sections_path
      post admin_sales_storefront_sections_path(section_type: "promo_banner")
      section = storefront.sections.find_by!(section_type: "promo_banner")
      expect(response).to redirect_to(edit_admin_sales_storefront_section_path(section))
      expect(section.position).to eq(StorefrontSection::DEFAULT_LAYOUT.size)

      get edit_admin_sales_storefront_section_path(section)
      expect(response).to have_http_status(:ok)

      patch admin_sales_storefront_section_path(section), params: {
        enabled: "1", image: photo,
        settings: { title: "Offer", title_ar: "عرض", link: "https://example.com", button_label: "Go", junk: "x" }
      }
      expect(response).to redirect_to(edit_admin_sales_storefront_section_path(section))
      expect(section.reload.settings).to include("title" => "Offer", "title_ar" => "عرض", "link" => "https://example.com")
      expect(section.settings).not_to have_key("junk")
      expect(section.image).to be_attached
    end

    it "refuses an unsafe button link" do
      section = StorefrontSection.create!(storefront: storefront, section_type: "promo_banner")

      patch admin_sales_storefront_section_path(section), params: { settings: { link: "javascript:alert(1)" } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(section.reload.setting(:link)).to be_nil
    end

    it "hides, moves, reorders and removes blocks" do
      get admin_sales_storefront_sections_path
      hero, categories = storefront.sections.first(2)

      patch toggle_admin_sales_storefront_section_path(hero)
      expect(hero.reload).not_to be_enabled

      patch move_admin_sales_storefront_section_path(categories, direction: "up")
      expect(storefront.sections.reload.first).to eq(categories)

      ids = storefront.sections.pluck(:id).reverse
      patch reorder_admin_sales_storefront_sections_path, params: { positions: ids.each_with_index.to_h }, as: :json
      expect(response).to have_http_status(:ok)
      expect(storefront.sections.reload.pluck(:id)).to eq(ids)

      delete admin_sales_storefront_section_path(hero)
      expect(storefront.sections.reload.pluck(:position)).to eq((0...(StorefrontSection::DEFAULT_LAYOUT.size - 1)).to_a)
    end

    it "won't add a second all-products grid" do
      get admin_sales_storefront_sections_path

      post admin_sales_storefront_sections_path(section_type: "all_products")

      expect(response).to redirect_to(admin_sales_storefront_sections_path)
      expect(storefront.sections.where(section_type: "all_products").count).to eq(1)
    end

    it "manages brand logos one by one" do
      section = StorefrontSection.create!(storefront: storefront, section_type: "brand_logos")

      patch admin_sales_storefront_section_path(section), params: { logos: [photo] }
      patch admin_sales_storefront_section_path(section), params: { logos: [fixture_file_upload("storefront_product.png", "image/png")] }
      expect(section.reload.logos.count).to eq(2)

      delete remove_logo_admin_sales_storefront_section_path(section, attachment_id: section.ordered_logos.first.id)
      expect(section.reload.logos.count).to eq(1)
    end
  end

  describe "website pages" do
    let!(:storefront) { Storefront.create!(company: company, enabled: true) }

    before { sign_in owner }

    it "lists the four pages and creates one on first save" do
      get admin_sales_storefront_pages_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Delivery &amp; returns", "Privacy policy")

      get edit_admin_sales_storefront_page_path("delivery-returns")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("trix-editor")

      patch admin_sales_storefront_page_path("delivery-returns"), params: {
        storefront_page: { enabled: "1", title: "Shipping", body: "<p>Cairo in 2 days</p>", body_ar: "<p>القاهرة خلال يومين</p>" }
      }

      expect(response).to redirect_to(admin_sales_storefront_pages_path)
      page = storefront.pages.sole
      expect(page).to have_attributes(slot: "delivery_returns", enabled: true, title: "Shipping")
      expect(page.body.to_plain_text).to eq("Cairo in 2 days")
      expect(page.body_ar.to_plain_text).to eq("القاهرة خلال يومين")
    end

    it "404s for a slot that doesn't exist" do
      get edit_admin_sales_storefront_page_path("blog")

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "dashboard quick link" do
    before { sign_in owner }

    it "links to the published website" do
      Storefront.create!(company: company, enabled: true)

      get admin_root_path

      expect(response.body).to include(public_storefront_home_url(company_slug: company.slug))
      expect(response.body).to include(I18n.t("dashboard.view_website"))
    end

    it "prefers the subdomain link when one is set" do
      Storefront.create!(company: company, enabled: true, subdomain: "acme")

      get admin_root_path

      expect(response.body).to include("http://acme.localhost")
    end

    it "is absent while the website is unpublished" do
      Storefront.create!(company: company, enabled: false)

      get admin_root_path

      expect(response.body).not_to include(I18n.t("dashboard.view_website"))
    end
  end

  it "shows the website in the sales sidebar" do
    sign_in owner

    get admin_sales_storefront_listings_path

    expect(response.body).to include(admin_sales_storefront_path)
  end
end
