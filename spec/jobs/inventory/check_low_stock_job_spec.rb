# frozen_string_literal: true

require "rails_helper"

RSpec.describe Inventory::CheckLowStockJob, type: :job do
  let(:category) { create(:ingredient_category) }
  let(:ingredient) do
    create(:ingredient, ingredient_category: category, name: "Lettuce",
      quantity_on_hand: 1, reorder_threshold: 10)
  end
  let(:supplier) { Supplier.create!(name: "Fresh Farms", lead_time_days: 1, company: Current.company) }

  let!(:owner) { create(:user, :owner) }
  let!(:manager) { create(:user, role: "manager") }

  def link_supplier!(skip:)
    supplier.update!(skip_stock_alerts: skip)
    SupplierIngredient.create!(supplier: supplier, ingredient: ingredient, price_cents: 100)
  end

  it "notifies managers when the ingredient is low and no supplier suppresses alerts" do
    link_supplier!(skip: false)

    expect { described_class.perform_now(ingredient.id) }
      .to change(Notification, :count).by(2)
  end

  it "does not notify when a linked supplier is flagged daily-fresh" do
    link_supplier!(skip: true)

    expect { described_class.perform_now(ingredient.id) }
      .not_to change(Notification, :count)
  end

  it "suppresses when any linked supplier is flagged, even alongside a non-flagged one" do
    link_supplier!(skip: false)
    other = Supplier.create!(name: "Daily Greens", lead_time_days: 1, company: Current.company, skip_stock_alerts: true)
    SupplierIngredient.create!(supplier: other, ingredient: ingredient, price_cents: 120)

    # Any flagged supplier suppresses the alert (fresh-goods behavior wins).
    expect { described_class.perform_now(ingredient.id) }
      .not_to change(Notification, :count)
  end

  it "does nothing when the ingredient is not low" do
    ingredient.update!(quantity_on_hand: 50)
    link_supplier!(skip: false)

    expect { described_class.perform_now(ingredient.id) }
      .not_to change(Notification, :count)
  end
end
