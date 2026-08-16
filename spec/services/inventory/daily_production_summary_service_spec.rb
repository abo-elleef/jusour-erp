# frozen_string_literal: true

require "rails_helper"

RSpec.describe Inventory::DailyProductionSummaryService do
  let(:company) { Current.company }
  let(:user) { create(:user, :owner, company: company) }
  let(:category) { create(:ingredient_category, company: company) }
  let(:kitchen) { create(:location, :central_kitchen, company: company, name: "CK") }
  let(:branch) { create(:location, company: company, name: "Branch") }
  let(:input) { create(:ingredient, company: company, ingredient_category: category, name: "Tomato") }
  let(:sauce) { create(:ingredient, company: company, ingredient_category: category, name: "Sauce") }
  let(:dough) { create(:ingredient, company: company, ingredient_category: category, name: "Dough") }

  def template_for(output, name:, yield_qty:)
    template = ManufacturingTemplate.create!(
      company: company, name: name, yield_quantity: yield_qty,
      active: false, output_ingredient: output, yield_unit: output.unit
    )
    template.manufacturing_template_lines.create!(ingredient: input, quantity_used: 1, unit: input.unit)
    template.update!(active: true)
    template
  end

  def run!(template:, location:, runs_count:, occurred_on:, notes: nil, shelf_life_days: 3, reversed_at: nil)
    ManufacturingRun.create!(
      company: company,
      manufacturing_template: template,
      user: user,
      location: location,
      runs_count: runs_count,
      occurred_on: occurred_on,
      shelf_life_days: shelf_life_days,
      notes: notes,
      reversed_at: reversed_at,
      reversed_by: reversed_at ? user : nil
    )
  end

  it "groups by output ingredient and sums produced quantity" do
    sauce_a = template_for(sauce, name: "Sauce A", yield_qty: 2)
    sauce_b = template_for(sauce, name: "Sauce B", yield_qty: 3)
    dough_t = template_for(dough, name: "Dough T", yield_qty: 1)
    day = Date.current

    runs = [
      run!(template: sauce_a, location: kitchen, runs_count: 2, occurred_on: day, notes: "First"),
      run!(template: sauce_b, location: branch, runs_count: 1, occurred_on: day, notes: "Second", shelf_life_days: 5),
      run!(template: dough_t, location: kitchen, runs_count: 4, occurred_on: day)
    ]

    rows = described_class.new(runs: runs).call
    expect(rows.map { |r| r.ingredient.name }).to eq(%w[Dough Sauce])

    sauce_row = rows.find { |r| r.ingredient == sauce }
    expect(sauce_row.total_quantity).to eq(7) # (2*2) + (1*3)
    expect(sauce_row.run_count).to eq(2)
    expect(sauce_row.locations).to contain_exactly("CK", "Branch")
    expect(sauce_row.notes).to contain_exactly("First", "Second")
    expect(sauce_row.expires_on_dates).to eq([day + 3, day + 5])
  end
end
