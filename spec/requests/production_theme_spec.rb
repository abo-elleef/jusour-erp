# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Production screen theme", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let(:owner) { create(:user, :owner, company: company) }

  before do
    Current.company = company
    sign_in owner
  end

  describe "the production sheet" do
    before { get production_path }

    it "renders dark server-side so a JS-less load still looks like it always has" do
      expect(response.body).to match(/<html[^>]*class="[^"]*\bdark\b/)
    end

    it "offers the toggle" do
      expect(response.body).to include('data-action="kitchen-theme#toggle"')
      expect(response.body).to include(I18n.t("production.theme.toggle"))
    end

    it "marks itself themeable for the Stimulus controller" do
      expect(response.body).to include('data-kitchen-theme-themeable-value="true"')
    end

    it "strips the class before first paint when light is stored" do
      # Inline head script — without it, choosing light flashes dark on every load.
      expect(response.body).to include('localStorage.getItem("kitchenTheme")')
      expect(response.body).to include('classList.remove("dark")')
    end

    it "carries the dark colour variants the toggle switches between" do
      expect(response.body).to include("dark:bg-gray-900")
    end
  end

  describe "the kitchen display" do
    before { get kitchen_path }

    it "stays pinned dark with no toggle — it is a wall-mounted screen" do
      expect(response.body).to match(/<html[^>]*class="[^"]*\bdark\b/)
      expect(response.body).not_to include('data-action="kitchen-theme#toggle"')
      expect(response.body).to include('data-kitchen-theme-themeable-value="false"')
    end
  end

  describe "the admin copy of the same bulk sheet" do
    # A template is required so the table body renders — that is where the row
    # striping and cell colours live, and those are what must stay light.
    let(:category) { create(:ingredient_category, company: company) }
    let(:output) { create(:ingredient, company: company, ingredient_category: category) }

    let(:input_ingredient) { create(:ingredient, company: company, ingredient_category: category) }

    before do
      # An active template needs at least one input line.
      template = ManufacturingTemplate.create!(company: company, name: "Sauce Batch",
        yield_quantity: 2, output_ingredient: output, active: false)
      template.manufacturing_template_lines.create!(ingredient: input_ingredient,
        quantity_used: 3, unit: input_ingredient.unit)
      template.update!(active: true)
    end

    it "emits no dark variants at all, so a stray .dark cannot darken it" do
      get new_admin_inventory_manufacturing_run_path

      expect(response.body).to include("Sauce Batch")
      expect(response.body).not_to include("dark:")
    end
  end
end
