# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Public menus", type: :request do
  include ApplicationHelper

  let(:company) { create(:company, slug: "acme-cafe", name: "Acme Cafe") }
  let!(:branch) do
    create(:location, company: company, name: "Downtown", slug: "downtown", location_type: "branch", active: true)
  end
  let!(:category) { create(:category, company: company, name: "Mains") }
  let!(:menu_item) do
    create(:menu_item, company: company, category: category, name: "Burger", base_price_cents: 1500, available: true)
  end
  let!(:location_menu_item) do
    create(:location_menu_item, location: branch, menu_item: menu_item, available: true)
  end

  before { Current.company = company }

  describe "GET /m/:company_slug" do
    it "shows branch picker without login" do
      create(:location, company: company, name: "Uptown", slug: "uptown", location_type: "branch", active: true)

      get public_menus_path(company_slug: company.slug)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Downtown")
      expect(response.body).to include("Uptown")
    end

    it "redirects to the menu when only one branch exists" do
      get public_menus_path(company_slug: company.slug)

      expect(response).to redirect_to(public_menu_path(company_slug: company.slug, location_slug: branch.slug))
    end
  end

  describe "GET /m/:company_slug/:location_slug" do
    it "shows the branch menu without login" do
      get public_menu_path(company_slug: company.slug, location_slug: branch.slug)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Burger")
      expect(response.body).to include("Downtown")
      expect(response.body).to include(format_money(1500))
    end

    it "returns not found for inactive company" do
      company.update!(active: false)

      get public_menu_path(company_slug: company.slug, location_slug: branch.slug)

      expect(response).to have_http_status(:not_found)
    end
  end
end
