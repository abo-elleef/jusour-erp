# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "sales:backfill_customer_owners" do
  before(:all) { Rails.application.load_tasks if Rake::Task.tasks.empty? }

  let(:task) { Rake::Task["sales:backfill_customer_owners"] }
  let(:company) { create(:company, business_type: "distribution") }

  before do
    task.reenable
    Current.company = company
    ENV["COMPANY"] = company.id
  end

  after { ENV.delete("COMPANY") }

  let(:owner) { create(:user, :owner, company: company) }
  let(:rep) { create(:user, company: company, name: "Rep One") }
  let(:location) { create(:location, company: company) }
  let(:category) { create(:ingredient_category, company: company) }
  let(:ingredient) { create(:ingredient, company: company, ingredient_category: category, name: "Kit", unit: "kg") }

  def invoice_for(customer, salesperson:, date:)
    inv = CustomerInvoice.new(company: company, customer: customer, user: owner, salesperson: salesperson,
      location: location, invoice_date: date)
    inv.customer_invoice_lines.build(ingredient: ingredient, quantity: 1, unit: ingredient.unit, unit_price_cents: 10_000)
    inv.save!
    inv
  end

  it "never assigns a customer to the owner; falls back to the latest invoice sold by someone else" do
    owner_only = create(:customer, company: company, name: "Owner Only Clinic")
    mixed = create(:customer, company: company, name: "Mixed Clinic")
    invoice_for(owner_only, salesperson: owner, date: Date.current)
    invoice_for(mixed, salesperson: rep, date: 2.days.ago.to_date)
    invoice_for(mixed, salesperson: owner, date: Date.current)

    expect { task.invoke }.to output(/staying unassigned: 1/).to_stdout

    expect(owner_only.reload.assigned_user_id).to be_nil
    expect(mixed.reload.assigned_user_id).to eq(rep.id)
  end
end
