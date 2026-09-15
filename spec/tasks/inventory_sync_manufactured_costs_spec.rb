# frozen_string_literal: true

require "rails_helper"
require "rake"

# The costing itself is covered in
# spec/services/inventory/sync_manufactured_cost_service_spec.rb. What only the
# task can get wrong is the tenant loop — the service reads through Ingredient's
# default scope, so a company left unset or leaked between iterations would
# silently sync the wrong books, or nothing at all.
RSpec.describe "inventory:sync_manufactured_costs" do
  before(:all) { Rails.application.load_tasks if Rake::Task.tasks.empty? }

  let(:task) { Rake::Task["inventory:sync_manufactured_costs"] }

  before { task.reenable }

  # A company with one manufactured output marked derived, holding a single
  # batch at +batch_cost+.
  def company_with_manufactured_output(batch_cost:)
    company = create(:company)
    previous = Current.company
    Current.company = company

    category = IngredientCategory.create!(name: "Prep", position: 1, company: company)
    input = Ingredient.create!(name: "Input #{company.slug}", ingredient_category: category,
      unit: "kg", cost_per_unit_cents: 100, quantity_on_hand: 10)
    output = Ingredient.create!(name: "Output #{company.slug}", ingredient_category: category,
      unit: "kg", cost_per_unit_cents: 0, cost_source: "derived", quantity_on_hand: 0)

    template = ManufacturingTemplate.create!(name: "Make #{company.slug}",
      output_ingredient: output, yield_quantity: 5, active: false)
    ManufacturingTemplateLine.create!(manufacturing_template: template, ingredient: input, quantity_used: 4)
    template.update!(active: true)

    StockBatch.create!(ingredient: output, location: create(:location, :central_kitchen, company: company),
      quantity_received: 10, quantity_remaining: 10, cost_per_unit_cents: batch_cost,
      received_on: Date.current)

    [company, output]
  ensure
    Current.company = previous
  end

  it "syncs derived costs in every company, not just the current one" do
    _first_company, first_output = company_with_manufactured_output(batch_cost: 250)
    _second_company, second_output = company_with_manufactured_output(batch_cost: 900)

    expect { task.invoke }.to output(/2 cost\(s\) updated/).to_stdout

    expect(first_output.reload.cost_per_unit_cents).to eq(250)
    expect(second_output.reload.cost_per_unit_cents).to eq(900)
  end

  it "restores the ambient company when it finishes" do
    company_with_manufactured_output(batch_cost: 250)
    ambient = Current.company

    expect { task.invoke }.to output.to_stdout

    expect(Current.company).to eq(ambient)
  end

  it "reports nothing changed on a second run" do
    _company, output = company_with_manufactured_output(batch_cost: 250)

    expect { task.invoke }.to output(/1 cost\(s\) updated/).to_stdout
    synced_at = output.reload.cost_synced_at

    task.reenable
    expect { task.invoke }.to output(/0 cost\(s\) updated/).to_stdout
    expect(output.reload.cost_synced_at).to eq(synced_at)
  end
end
