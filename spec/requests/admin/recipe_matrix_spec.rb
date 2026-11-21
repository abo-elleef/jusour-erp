# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin recipe matrix", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { Current.company }
  let(:owner) { create(:user, :owner, company: company, wages_account_code: 2501) }
  let(:meat) { create(:ingredient, company: company, name: "Beef", unit: "kg", cost_per_unit_cents: 30_000) }
  let(:bun) { create(:ingredient, company: company, name: "Bun", unit: "pieces", cost_per_unit_cents: 200) }
  let(:sauce) { create(:ingredient, company: company, name: "Regular sauce", unit: "kg", cost_per_unit_cents: 5_000) }
  let!(:hot_sauce) { create(:ingredient, company: company, name: "Hot sauce", unit: "kg", cost_per_unit_cents: 8_000) }
  let(:sandwich) { create(:menu_item, company: company, name: "Sandwich") }
  let(:size) { ModifierGroup.create!(company: company, name: "Size", required: true) }
  let(:spice) { ModifierGroup.create!(company: company, name: "Spice", required: true) }
  let(:extras) { ModifierGroup.create!(company: company, name: "Extras", multi_select: true) }
  let!(:single) { size.modifiers.create!(company: company, name: "Single", position: 0) }
  let!(:double) { size.modifiers.create!(company: company, name: "Double", position: 1) }
  let!(:not_spicy) { spice.modifiers.create!(company: company, name: "Not spicy", position: 0) }
  let!(:spicy) { spice.modifiers.create!(company: company, name: "Spicy", position: 1) }

  before do
    sign_in owner
    Recipe.create!(menu_item: sandwich, ingredient: meat, quantity_used: 0.1, unit: "kg")
    Recipe.create!(menu_item: sandwich, ingredient: bun, quantity_used: 1, unit: "pieces")
    Recipe.create!(menu_item: sandwich, ingredient: sauce, quantity_used: 0.02, unit: "kg")
    ModifierRecipe.create!(modifier: double, ingredient: meat, quantity: 0.1, unit: "kg")
    [size, spice, extras].each_with_index do |group, i|
      MenuItemModifierGroup.create!(menu_item: sandwich, modifier_group: group, position: i)
    end
  end

  def matrix_rows
    get edit_admin_menu_item_path(sandwich)
    Nokogiri::HTML(response.body).css("#recipe-matrix table.min-w-full > tbody > tr").map { |tr| tr.text.squish }
  end

  it "ticks the groups that change the recipe and lists every combination" do
    patch recipe_matrix_admin_menu_item_path(sandwich), params: { group_ids: [size.id, spice.id] }
    expect(sandwich.menu_item_modifier_groups.where(recipe_matrix: true).map(&:modifier_group)).to contain_exactly(size, spice)

    rows = matrix_rows
    expect(rows.size).to eq(4)
    expect(rows.find { |r| r.start_with?("Double Spicy") }).to include("Beef 0.2", "Regular sauce 0.02")
  end

  it "refuses to tick a multiple-choice group" do
    patch recipe_matrix_admin_menu_item_path(sandwich), params: { group_ids: [extras.id] }
    expect(flash[:alert]).to be_present
    expect(sandwich.menu_item_modifier_groups.where(recipe_matrix: true)).to be_empty
  end

  context "with Size and Spice ticked" do
    before { patch recipe_matrix_admin_menu_item_path(sandwich), params: { group_ids: [size.id, spice.id] } }

    it "customises a row starting from what it used, then edits it" do
      post admin_menu_item_combination_recipes_path(sandwich), params: { modifier_ids: [spicy.id, double.id] }
      recipe = sandwich.combination_recipes.sole
      expect(response).to redirect_to(edit_admin_menu_item_combination_recipe_path(sandwich, recipe))
      expect(recipe.lines.to_h { |l| [l.ingredient.name, l.quantity.to_d] })
        .to eq("Beef" => 0.2.to_d, "Bun" => 1, "Regular sauce" => 0.02.to_d)

      sauce_line = recipe.lines.find_by(ingredient: sauce)
      delete admin_menu_item_combination_recipe_line_path(sandwich, recipe, sauce_line)
      post admin_menu_item_combination_recipe_lines_path(sandwich, recipe),
        params: { line: { ingredient_id: hot_sauce.id, quantity: "0.04", unit: "kg" } }
      bun_line = recipe.lines.find_by(ingredient: bun)
      patch admin_menu_item_combination_recipe_line_path(sandwich, recipe, bun_line), params: { line: { quantity: "2" } }

      expect(recipe.reload.lines.to_h { |l| [l.ingredient.name, l.quantity.to_d] })
        .to eq("Beef" => 0.2.to_d, "Bun" => 2, "Hot sauce" => 0.04.to_d)
      # The custom row marks what differs from the automatic recipe.
      added, changed, removed = %w[added changed removed].map { |k| I18n.t("menu.recipe_matrix.change_#{k}", locale: :ar) }
      row = matrix_rows.find { |r| r.start_with?("Double Spicy") }
      # Added: "+", changed: "~" with the automatic quantity (1) before the new one (2).
      expect(row).to include("Hot sauce + #{added} 0.04", "Bun ~ #{changed} 1 2", "Beef 0.2", "Regular sauce #{removed}")

      get edit_admin_menu_item_combination_recipe_path(sandwich, recipe)
      expect(response).to have_http_status(:ok)
    end

    it "copies another row and goes back to auto" do
      post admin_menu_item_combination_recipes_path(sandwich), params: { modifier_ids: [double.id, spicy.id] }
      source = sandwich.combination_recipes.sole
      source.lines.find_by(ingredient: sauce).update!(ingredient: hot_sauce, quantity: 0.04)
      post admin_menu_item_combination_recipes_path(sandwich), params: { modifier_ids: [single.id, spicy.id] }
      target = sandwich.combination_recipes.where.not(id: source.id).sole

      post copy_admin_menu_item_combination_recipe_path(sandwich, target), params: { source_id: source.id }
      expect(target.reload.lines.map(&:ingredient)).to contain_exactly(meat, bun, hot_sauce)

      delete admin_menu_item_combination_recipe_path(sandwich, target)
      expect(CombinationRecipe.exists?(target.id)).to be(false)
    end
  end
end
