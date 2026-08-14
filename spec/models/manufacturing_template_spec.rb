# frozen_string_literal: true

require "rails_helper"

RSpec.describe ManufacturingTemplate, type: :model do
  let(:category) { create(:ingredient_category) }
  let(:output) { create(:ingredient, ingredient_category: category, name: "Meatballs") }
  let(:meat) { create(:ingredient, ingredient_category: category, name: "Raw Meat") }
  let(:breadcrumbs) { create(:ingredient, ingredient_category: category, name: "Breadcrumbs") }
  let(:non_input) { create(:ingredient, ingredient_category: category, name: "Unrelated") }

  def template_with_lines(active: true, **attrs)
    t = ManufacturingTemplate.create!(name: "Meatballs Batch", output_ingredient: output,
      yield_quantity: 11, active: false, **attrs)
    t.manufacturing_template_lines.create!(ingredient: meat, quantity_used: 10, unit: meat.unit)
    t.manufacturing_template_lines.create!(ingredient: breadcrumbs, quantity_used: 2, unit: breadcrumbs.unit)
    t.update!(active: active) if active
    t
  end

  describe "control_mode" do
    it "defaults to runs" do
      expect(ManufacturingTemplate.new.control_mode).to eq("runs")
    end

    it "rejects an unknown control mode" do
      t = template_with_lines(active: false)
      t.control_mode = "bogus"
      expect(t).not_to be_valid
      expect(t.errors[:control_mode]).to be_present
    end

    it "#main_ingredient_controlled? reflects the mode" do
      expect(ManufacturingTemplate.new(control_mode: "main_ingredient").main_ingredient_controlled?).to be(true)
      expect(ManufacturingTemplate.new(control_mode: "runs").main_ingredient_controlled?).to be(false)
    end
  end

  describe "#main_line" do
    it "returns the input line matching the main ingredient" do
      t = template_with_lines
      t.update!(control_mode: "main_ingredient", main_ingredient_id: meat.id)
      expect(t.main_line.ingredient).to eq(meat)
    end

    it "is nil when no main ingredient is set" do
      expect(template_with_lines.main_line).to be_nil
    end
  end

  describe "main-ingredient validation" do
    it "is valid when the main ingredient is one of the input lines" do
      t = template_with_lines
      t.assign_attributes(control_mode: "main_ingredient", main_ingredient_id: meat.id)
      expect(t).to be_valid
    end

    it "requires a main ingredient in main-ingredient mode" do
      t = template_with_lines
      t.assign_attributes(control_mode: "main_ingredient", main_ingredient_id: nil)
      expect(t).not_to be_valid
      expect(t.errors[:main_ingredient_id]).to be_present
    end

    it "rejects a main ingredient that is not one of the input lines" do
      t = template_with_lines
      t.assign_attributes(control_mode: "main_ingredient", main_ingredient_id: non_input.id)
      expect(t).not_to be_valid
      expect(t.errors[:main_ingredient_id]).to be_present
    end

    it "does not require a main ingredient in runs mode" do
      t = template_with_lines
      t.assign_attributes(control_mode: "runs", main_ingredient_id: nil)
      expect(t).to be_valid
    end
  end
end
