# frozen_string_literal: true

require "rails_helper"

RSpec.describe Accounting::OrderNotesService do
  let(:company) { create(:company) }
  let(:owner) { create(:user, :owner, company: company, wages_account_code: 2501) }
  let(:mains) { create(:category, company: company, name: "Mains") }
  let(:drinks) { create(:category, company: company, name: "Drinks") }
  let(:burger) { create(:menu_item, company: company, category: mains, name: "Burger", base_price_cents: 1000) }
  let(:cola) { create(:menu_item, company: company, category: drinks, name: "Cola", base_price_cents: 300) }
  let(:size) { ModifierGroup.create!(company: company, name: "Size") }
  let(:double) { size.modifiers.create!(company: company, name: "Double", price_adjustment_cents: 500) }
  let(:today) { Date.current }

  before { Current.company = company }

  # Noon, so the order falls on today's business day whatever time the suite runs.
  def order!(status: "completed", notes: nil, location: nil)
    create(:order, user: owner, company: company, status: status, notes: notes, location: location,
                   subtotal_cents: 1000, total_cents: 1000, created_at: Time.zone.now.change(hour: 12))
  end

  def line!(order, item, notes: nil, choice: nil)
    line = create(:order_item, order: order, menu_item: item, quantity: 1, unit_price_cents: 1000, notes: notes)
    line.order_item_modifiers.create!(modifier: choice, name: choice.name, price_adjustment_cents: 0) if choice
    line
  end

  def service(**opts)
    described_class.new(today, today, **opts)
  end

  def texts(**opts)
    service(**opts).notes.map { |n| n[:text] }
  end

  let!(:order_a) do
    order!(notes: "Deliver to gate 3").tap do |o|
      line!(o, burger, notes: "No onion", choice: double)
      line!(o, cola)
    end
  end
  let!(:order_b) do
    order!.tap do |o|
      line!(o, burger, notes: "Well done")
      line!(o, cola, notes: "  ")
    end
  end

  it "lists item and order notes, leaving blank ones out" do
    expect(texts).to contain_exactly("Deliver to gate 3", "No onion", "Well done")
    expect(service.notes.find { |n| n[:text] == "No onion" }).to include(kind: :item, item_name: "Burger", category: "Mains", modifiers: ["Double"])
  end

  it "only reads the orders the Sales report counts" do
    order!(status: "cancelled", notes: "Cancelled note")
    order!(status: "in_progress", notes: "Open note")
    expect(texts).not_to include("Cancelled note", "Open note")
    expect(texts(include_open: true)).to include("Open note")
    expect(texts(include_open: true)).not_to include("Cancelled note")
  end

  it "filters by kind and by words in the note" do
    expect(texts(kind: "order")).to eq(["Deliver to gate 3"])
    expect(texts(kind: "item")).to contain_exactly("No onion", "Well done")
    expect(texts(query: "onion")).to eq(["No onion"])
  end

  it "filters by item: its notes plus the order notes of orders that have it" do
    expect(texts(item: "m:#{burger.id}")).to contain_exactly("Deliver to gate 3", "No onion", "Well done")
    expect(texts(item: "m:#{cola.id}")).to contain_exactly("Deliver to gate 3")
  end

  it "filters by category" do
    expect(texts(category: drinks.id)).to contain_exactly("Deliver to gate 3")
    expect(texts(category: "combos")).to be_empty
  end

  it "filters by modifier choice" do
    opts = { item: "m:#{burger.id}", modifier_group: "Size", modifier_choice: "Double" }
    expect(texts(**opts)).to contain_exactly("Deliver to gate 3", "No onion")
    expect(service.choice_options).to eq([])
    expect(service(item: "m:#{burger.id}").choice_options).to eq([%w[Size Double]])
  end

  it "filters by branch" do
    branch = create(:location, :branch, company: company)
    o = order!(notes: "Other branch", location: branch)
    line!(o, cola)
    expect(texts(location_id: branch.id)).to eq(["Other branch"])
    expect(texts).to include("Other branch")
  end

  it "counts what each filter would list" do
    counts = service.counts
    expect(counts[:total]).to eq(service.notes.size)
    expect(counts[:items]["m:#{burger.id}"]).to eq(texts(item: "m:#{burger.id}").size)
    expect(counts[:items]["m:#{cola.id}"]).to eq(texts(item: "m:#{cola.id}").size)
    expect(counts[:categories][mains.id]).to eq(texts(category: mains.id).size)
    expect(counts[:categories][drinks.id]).to eq(1)
    expect(counts[:choices][["m:#{burger.id}", "Size", "Double"]])
      .to eq(texts(item: "m:#{burger.id}", modifier_group: "Size", modifier_choice: "Double").size)
  end
end
