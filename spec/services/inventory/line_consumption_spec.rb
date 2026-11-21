# frozen_string_literal: true

require "rails_helper"

RSpec.describe Inventory::LineConsumption do
  let(:company) { create(:company) }
  let(:meat) { create(:ingredient, company: company, unit: "kg", cost_per_unit_cents: 30_000) }
  let(:bun) { create(:ingredient, company: company, unit: "pieces", cost_per_unit_cents: 200) }
  let(:sauce) { create(:ingredient, company: company, unit: "kg", cost_per_unit_cents: 5_000) }
  let(:hot_sauce) { create(:ingredient, company: company, unit: "kg", cost_per_unit_cents: 8_000) }
  let(:cheese) { create(:ingredient, company: company, unit: "kg", cost_per_unit_cents: 20_000) }

  let(:sandwich) { create(:menu_item, company: company) }
  let(:size) { ModifierGroup.create!(company: company, name: "Size", required: true) }
  let(:single) { size.modifiers.create!(company: company, name: "Single") }
  let(:double) { size.modifiers.create!(company: company, name: "Double") }
  let(:spice) { ModifierGroup.create!(company: company, name: "Spice", required: true) }
  let(:not_spicy) { spice.modifiers.create!(company: company, name: "Not spicy") }
  let(:spicy) { spice.modifiers.create!(company: company, name: "Spicy") }
  let(:extras) { ModifierGroup.create!(company: company, name: "Extras", multi_select: true) }
  let(:extra_cheese) { extras.modifiers.create!(company: company, name: "Cheese") }
  let!(:size_link) { MenuItemModifierGroup.create!(menu_item: sandwich, modifier_group: size, position: 0) }
  let!(:spice_link) { MenuItemModifierGroup.create!(menu_item: sandwich, modifier_group: spice, position: 1) }

  before do
    Current.company = company
    MenuItemModifierGroup.create!(menu_item: sandwich, modifier_group: extras, position: 2)
    Recipe.create!(menu_item: sandwich, ingredient: meat, quantity_used: 0.1, unit: "kg")
    Recipe.create!(menu_item: sandwich, ingredient: bun, quantity_used: 1, unit: "pieces")
    Recipe.create!(menu_item: sandwich, ingredient: sauce, quantity_used: 0.02, unit: "kg")
    ModifierRecipe.create!(modifier: double, ingredient: meat, quantity: 0.1, unit: "kg")
    ModifierRecipe.create!(modifier: extra_cheese, ingredient: cheese, quantity: 0.03, unit: "kg")
  end

  def totals(*modifiers)
    described_class.totals(menu_item: sandwich.reload, modifiers: modifiers.map(&:reload))
      .transform_keys(&:name).transform_values { |q| q.to_d.round(4) }
  end

  def matrix_row(*modifiers, **quantities)
    recipe = CombinationRecipe.create!(menu_item: sandwich, modifier_ids: modifiers.map(&:id))
    quantities.each { |ingredient, quantity| recipe.lines.create!(ingredient: send(ingredient), quantity: quantity) }
    recipe
  end

  it "adds up the item recipe and the options' own when no group is ticked" do
    expect(totals(double, spicy, extra_cheese)).to eq(
      meat.name => 0.2.to_d, bun.name => 1, sauce.name => 0.02.to_d, cheese.name => 0.03.to_d
    )
  end

  context "with Size and Spice ticked" do
    before do
      size_link.update!(recipe_matrix: true)
      spice_link.update!(recipe_matrix: true)
      matrix_row(double, spicy, meat: 0.2, bun: 1, hot_sauce: 0.04)
    end

    it "uses the row's full recipe in place of the item recipe and the ticked options' own" do
      expect(totals(double, spicy)).to eq(meat.name => 0.2.to_d, bun.name => 1, hot_sauce.name => 0.04.to_d)
    end

    it "still adds the options of groups outside the matrix" do
      expect(totals(double, spicy, extra_cheese)).to include(cheese.name => 0.03.to_d, hot_sauce.name => 0.04.to_d)
    end

    it "adds up as before for a combination with no saved row" do
      expect(totals(double, not_spicy)).to eq(meat.name => 0.2.to_d, bun.name => 1, sauce.name => 0.02.to_d)
    end

    it "costs the row's lines" do
      lines = described_class.call(menu_item: sandwich.reload, modifiers: [double.reload, spicy.reload])
      expect(lines.sum(&:cost_cents)).to eq(6_000 + 200 + 320)
    end

    it "matches the row whatever order the options were chosen in" do
      expect(totals(spicy, double)).to eq(totals(double, spicy))
    end
  end

  describe "rules" do
    it "starts the matrix over when the ticked groups change" do
      size_link.update!(recipe_matrix: true)
      matrix_row(double, meat: 0.2)
      expect { spice_link.update!(recipe_matrix: true) }.to change(CombinationRecipe, :count).to(0)
    end

    it "starts the matrix over when a ticked group is taken off the item" do
      size_link.update!(recipe_matrix: true)
      matrix_row(double, meat: 0.2)
      expect { size_link.destroy! }.to change(CombinationRecipe, :count).to(0)
    end

    it "refuses to tick a multiple-choice group" do
      link = sandwich.menu_item_modifier_groups.find_by(modifier_group: extras)
      expect(link.update(recipe_matrix: true)).to be(false)
    end
  end
end
