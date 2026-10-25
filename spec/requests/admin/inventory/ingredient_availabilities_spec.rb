# frozen_string_literal: true

require "rails_helper"

# The per-ingredient edit form still scopes an ingredient to locations. This
# page is that same choice for the whole catalog at once.
RSpec.describe "Ingredient location access", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { Current.company }

  # users.wages_account_code is NOT NULL with nothing in the app that sets it.
  # Same workaround as the storefront request specs.
  def staff(*traits)
    @wages_codes = (@wages_codes || 2500) + 1
    create(:user, *traits, company: company, wages_account_code: @wages_codes)
  end

  let(:owner) { staff(:owner) }
  let(:category) { IngredientCategory.create!(name: "Produce", position: 1, company: company) }
  let!(:branch_a) { Location.create!(name: "Branch A", location_type: "branch", company: company) }
  let!(:branch_b) { Location.create!(name: "Branch B", location_type: "branch", company: company) }
  let!(:everywhere) do
    Ingredient.create!(name: "Tomatoes", ingredient_category: category, unit: "kg",
      reorder_threshold: 1, company: company)
  end
  let!(:limited) do
    Ingredient.create!(name: "Salt", ingredient_category: category, unit: "kg",
      reorder_threshold: 1, company: company, all_locations: false,
      restricted_location_ids: [branch_a.id])
  end

  before { sign_in owner }

  it "lists every ingredient against every active location" do
    get admin_inventory_ingredient_availabilities_path

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    expect(html.at_css("#availability_#{everywhere.id}_all")["checked"]).to eq("checked")
    expect(html.at_css("#availability_#{everywhere.id}_#{branch_b.id}")["checked"]).to eq("checked")
    expect(html.at_css("#availability_#{limited.id}_all")["checked"]).to be_nil
    expect(html.at_css("#availability_#{limited.id}_#{branch_a.id}")["checked"]).to eq("checked")
    expect(html.at_css("#availability_#{limited.id}_#{branch_b.id}")["checked"]).to be_nil
  end

  it "links here from the ingredient edit form" do
    get edit_admin_inventory_ingredient_path(everywhere)

    expect(response.body).to include(admin_inventory_ingredient_availabilities_path)
  end

  it "filters to ingredients that are limited to specific locations" do
    get admin_inventory_ingredient_availabilities_path(availability: "limited")

    expect(response.body).to include("Salt")
    expect(response.body).not_to include("Tomatoes")
  end

  it "filters to ingredients usable at a location, like the ingredients index" do
    pepper = Ingredient.create!(name: "Pepper", ingredient_category: category, unit: "kg",
      reorder_threshold: 1, company: company, all_locations: false,
      restricted_location_ids: [branch_b.id])

    get admin_inventory_ingredient_availabilities_path(location_id: branch_a.id)

    html = Nokogiri::HTML(response.body)
    expect(html.at_css("#availability_#{everywhere.id}_all")).to be_present
    expect(html.at_css("#availability_#{limited.id}_all")).to be_present
    expect(html.at_css("#availability_#{pepper.id}_all")).to be_nil
  end

  it "shows each location's balance under its checkbox, negatives in red" do
    IngredientLocation.create!(ingredient: limited, location: branch_a, quantity_on_hand: 12.5)
    IngredientLocation.create!(ingredient: limited, location: branch_b, quantity_on_hand: -2)

    get admin_inventory_ingredient_availabilities_path

    html = Nokogiri::HTML(response.body)
    cell_balance = ->(ingredient, location) { html.at_css("#availability_#{ingredient.id}_#{location.id}").ancestors("td").first.at_css("[data-balance]") }
    expect(cell_balance.call(limited, branch_a).text).to include("12.5")
    expect(cell_balance.call(limited, branch_b).text).to include("-2")
    expect(cell_balance.call(limited, branch_b)["class"]).to include("text-red-600")
    expect(cell_balance.call(everywhere, branch_a).text.strip).to eq(I18n.t("accounting.shared.em_dash"))
  end

  it "offers a balances-only print that leaves out the access checkboxes" do
    get admin_inventory_ingredient_availabilities_path

    html = Nokogiri::HTML(response.body)
    button = html.at_css("button[data-controller='print-mode'][data-print-mode-mode-value='balances']")
    expect(button.text.strip).to eq(I18n.t("inventory.ingredient_availabilities.print_balances"))

    cell = html.at_css("#availability_#{limited.id}_#{branch_a.id}").ancestors("td").first
    expect(cell.at_css("[data-print-availability] #availability_#{limited.id}_#{branch_a.id}")).to be_present
    expect(cell.at_css("[data-balance]").ancestors("[data-print-availability]")).to be_empty
    expect(html.at_css("#availability_#{limited.id}_all").ancestors("td").first["data-print-availability"]).not_to be_nil
  end

  it "numbers the rows" do
    get admin_inventory_ingredient_availabilities_path

    row_numbers = Nokogiri::HTML(response.body).css("tbody tr").map { |row| row.css("td").first.text.strip }
    expect(row_numbers).to eq(%w[1 2])
  end

  it "exports the filtered grid as CSV, with access and balance per location" do
    IngredientLocation.create!(ingredient: limited, location: branch_a, quantity_on_hand: 12.5)
    IngredientLocation.create!(ingredient: limited, location: branch_b, quantity_on_hand: -2)

    get admin_inventory_ingredient_availabilities_path(format: :csv, location_id: branch_a.id)

    expect(response).to have_http_status(:ok)
    expect(response.headers["Content-Disposition"]).to include("ingredient-location-access-#{Date.current}.csv")
    rows = CSV.parse(response.body.delete_prefix("\uFEFF"))
    balance = ->(name) { I18n.t("inventory.ingredient_availabilities.csv.balance", location: name) }
    expect(rows.first.last(4)).to eq(["Branch A", balance.call("Branch A"), "Branch B", balance.call("Branch B")])
    yes = I18n.t("inventory.ingredient_availabilities.csv.yes")
    no = I18n.t("inventory.ingredient_availabilities.csv.no")
    by_name = rows.drop(1).index_by { |row| row[2] }
    expect(by_name["Tomatoes"].last(4)).to eq([yes, nil, yes, nil])
    expect(by_name["Salt"].last(4)).to eq([yes, "12.5", no, "-2"])
  end

  it "offers print and CSV export, hidden from the printout" do
    get admin_inventory_ingredient_availabilities_path

    html = Nokogiri::HTML(response.body)
    csv_link = html.at_css("a[href*='ingredient_availabilities.csv']")
    expect(csv_link).to be_present
    expect(csv_link.ancestors(".print-hide")).to be_present
    expect(html.at_css("button[onclick='window.print()']")).to be_present
  end

  describe "saving the grid" do
    it "limits an everywhere ingredient to the locations still checked" do
      untouched_at = limited.updated_at

      patch bulk_update_admin_inventory_ingredient_availabilities_path, params: {
        availabilities: {
          everywhere.id => { all_locations: "0", location_ids: [branch_a.id] },
          limited.id => { all_locations: "0", location_ids: [branch_a.id] }
        }
      }
      everywhere.reload

      expect(response).to redirect_to(admin_inventory_ingredient_availabilities_path)
      expect(flash[:notice]).to eq(I18n.t("inventory.ingredient_availabilities.saved", count: 1))
      expect(everywhere.all_locations).to be false
      expect(everywhere.restricted_location_ids).to eq([branch_a.id])
      expect(everywhere.can_access_location?(branch_a)).to be true
      expect(everywhere.can_access_location?(branch_b)).to be false
      expect(limited.reload.updated_at).to eq(untouched_at)
    end

    it "leaves a previously saved subset in place when turning all locations back on" do
      patch bulk_update_admin_inventory_ingredient_availabilities_path, params: {
        availabilities: {
          limited.id => { all_locations: "1", location_ids: [branch_a.id, branch_b.id] }
        }
      }
      limited.reload

      expect(limited.all_locations).to be true
      expect(limited.restricted_location_ids).to eq([branch_a.id])
      expect(limited.can_access_location?(branch_b)).to be true
    end

    it "keeps assignments to inactive locations, which this grid does not show" do
      closed = Location.create!(name: "Closed", location_type: "branch", active: false, company: company)
      limited.update!(restricted_location_ids: [branch_a.id, closed.id])

      patch bulk_update_admin_inventory_ingredient_availabilities_path, params: {
        availabilities: {
          limited.id => { all_locations: "0", location_ids: [branch_b.id] }
        }
      }

      expect(limited.reload.restricted_location_ids).to match_array([branch_b.id, closed.id])
    end

    it "ignores a location that belongs to another company" do
      other = create(:company)
      foreign = Location.unscoped.create!(
        name: "Elsewhere", slug: "elsewhere", location_type: "branch", company: other, active: true
      )

      patch bulk_update_admin_inventory_ingredient_availabilities_path, params: {
        availabilities: {
          everywhere.id => { all_locations: "0", location_ids: [branch_a.id, foreign.id] }
        }
      }

      expect(everywhere.reload.restricted_location_ids).to eq([branch_a.id])
    end

    it "records the effective scope on the ingredient's history" do
      patch bulk_update_admin_inventory_ingredient_availabilities_path, params: {
        availabilities: {
          everywhere.id => { all_locations: "0", location_ids: [branch_a.id] }
        }
      }

      audit = everywhere.audits.find_by!(action: "location_access_changed")
      expect(audit.user).to eq(owner)
      expect(audit.audited_changes["all_locations"]).to eq([true, false])
      expect(audit.audited_changes["location_access"]).to eq([
        I18n.t("inventory.ingredient_availabilities.scope_all"),
        branch_a.name
      ])

      get admin_inventory_ingredient_path(everywhere)
      expect(response.body).to include(I18n.t("accounting.audit_history.actions.location_access_changed"))
      expect(response.body).to include(branch_a.name)
    end

    it "turns away a user who may read inventory but not reshape it" do
      staff(:manager)
      role = Role.unscoped.find_by!(company_id: company.id, key: "manager")
      role.update!(permissions: role.permission_keys - ["inventory:settings"])
      sign_in User.find_by!(company: company, role: "manager")

      get admin_inventory_ingredient_availabilities_path
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(bulk_update_admin_inventory_ingredient_availabilities_path)

      patch bulk_update_admin_inventory_ingredient_availabilities_path, params: {
        availabilities: {
          everywhere.id => { all_locations: "0", location_ids: [branch_a.id] }
        }
      }

      expect(everywhere.reload.all_locations).to be true
    end
  end
end
