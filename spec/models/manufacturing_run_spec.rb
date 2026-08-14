# frozen_string_literal: true

require "rails_helper"

RSpec.describe ManufacturingRun, type: :model do
  let(:category) { create(:ingredient_category) }
  let(:output) { create(:ingredient, ingredient_category: category) }
  let(:location) { create(:location, :central_kitchen) }
  let(:user) { create(:user) }
  let(:template) do
    ManufacturingTemplate.create!(name: "Batch", yield_quantity: 1, output_ingredient: output, active: false)
  end

  def run(occurred_on: Date.current, number: nil)
    ManufacturingRun.create!(manufacturing_template: template, user: user, location: location,
      runs_count: 1, occurred_on: occurred_on, shelf_life_days: 3, run_number: number)
  end

  describe ".next_run_number" do
    it "returns a yearly MFG sequence for the company" do
      expect(described_class.next_run_number(company: Current.company, year: 2026)).to eq("MFG-2026-00001")
      run(number: "MFG-2026-00001")
      expect(described_class.next_run_number(company: Current.company, year: 2026)).to eq("MFG-2026-00002")
    end

    it "resets the sequence for a new year" do
      run(number: "MFG-2026-00009")
      expect(described_class.next_run_number(company: Current.company, year: 2027)).to eq("MFG-2027-00001")
    end
  end

  it "auto-assigns a run number (by the production year) on create" do
    r = run(occurred_on: Date.new(2026, 5, 1))
    expect(r.run_number).to eq("MFG-2026-00001")
  end

  it "is scoped to the company (tenant)" do
    expect(described_class.new.respond_to?(:company)).to be(true)
    expect(run.company).to eq(Current.company)
  end

  describe "#main_ingredient_driven?" do
    it "is true only when a main-input amount was recorded" do
      expect(run.main_ingredient_driven?).to be(false)

      driven = ManufacturingRun.create!(manufacturing_template: template, user: user, location: location,
        runs_count: 3, occurred_on: Date.current, shelf_life_days: 3, main_input_quantity: 12)
      expect(driven.main_ingredient_driven?).to be(true)
    end
  end
end
