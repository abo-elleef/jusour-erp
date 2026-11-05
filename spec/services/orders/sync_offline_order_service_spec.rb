# frozen_string_literal: true

require "rails_helper"

RSpec.describe Orders::SyncOfflineOrderService do
  include ActiveJob::TestHelper

  let(:company) { create(:company) }
  let(:branch) { create(:location, company: company) }
  let(:cashier) { create(:user, company: company, role: "cashier") }
  let(:other_cashier) { create(:user, company: company, role: "cashier", email: "other@example.com") }
  let(:category) { create(:category, company: company) }
  let(:burger) { create(:menu_item, company: company, category: category, name: "Burger", base_price_cents: 1000) }
  let(:cheese) do
    group = ModifierGroup.create!(company: company, name: "Extras")
    Modifier.create!(company: company, modifier_group: group, name: "Cheese", price_adjustment_cents: 200)
  end
  let(:uuid) { SecureRandom.uuid }

  before do
    Current.company = company
    TaxRate.create!(company: company, name: "VAT", rate: 0.14, tax_category: "food", active: true)
  end

  def payload(overrides = {})
    {
      client_uuid: uuid,
      offline_number: "OFF-7",
      created_at: 10.minutes.ago.iso8601,
      user_id: cashier.id,
      location_id: branch.id,
      order_type: "pickup",
      tendered_cents: 5000,
      items: [
        {
          menu_item_id: burger.id,
          quantity: 2,
          unit_price_cents: 1000,
          notes: "no onions",
          modifiers: [{ id: cheese.id, name: "Cheese", price_adjustment_cents: 200 }]
        }
      ]
    }.merge(overrides)
  end

  it "creates a paid, submitted order with its lines and modifiers" do
    result = described_class.call(user: cashier, payload: payload)

    expect(result).to be_success
    order = result.order
    expect(order.client_uuid).to eq(uuid)
    expect(order.offline_number).to eq("OFF-7")
    expect(order.status).to eq("submitted")
    expect(order.order_items.first.quantity).to eq(2)
    expect(order.order_items.first.order_item_modifiers.map(&:name)).to eq(["Cheese"])
    # (1000 + 200) × 2 = 2400, + 14% tax rounded per line = 336
    expect(order.subtotal_cents).to eq(2400)
    expect(order.tax_cents).to eq(336)
    expect(order.total_cents).to eq(2736)
    expect(order.payments.sole.amount_cents).to eq(5000)
    expect(order).to be_fully_paid
  end

  it "keeps the time the order was really rung up" do
    stamp = 25.minutes.ago.change(usec: 0)
    order = described_class.call(user: cashier, payload: payload(created_at: stamp.iso8601)).order

    expect(order.created_at).to eq(stamp)
    expect(order.payments.sole.created_at).to eq(stamp)
  end

  it "ignores a clock that is in the future or absurdly old" do
    future = described_class.call(user: cashier, payload: payload(created_at: 2.days.from_now.iso8601)).order
    expect(future.created_at).to be_within(1.minute).of(Time.current)

    old = described_class.call(user: cashier, payload: payload(client_uuid: SecureRandom.uuid, created_at: 30.days.ago.iso8601)).order
    expect(old.created_at).to be_within(1.minute).of(Time.current)
  end

  it "does not print anything — the customer and the kitchen already have their paper" do
    expect { described_class.call(user: cashier, payload: payload) }
      .not_to have_enqueued_job(Printing::DispatchProductionPrintsJob)
    expect { described_class.call(user: cashier, payload: payload(client_uuid: SecureRandom.uuid)) }
      .not_to have_enqueued_job(Printing::PrintReceiptJob)
  end

  it "is safe to repeat: the same client_uuid returns the order already made" do
    first = described_class.call(user: cashier, payload: payload)

    expect { @second = described_class.call(user: cashier, payload: payload) }.not_to change(Order, :count)

    expect(@second).to be_success
    expect(@second).to be_duplicate
    expect(@second.order).to eq(first.order)
    expect(Payment.where(order: first.order).count).to eq(1)
  end

  it "attributes the order to the cashier who rang it, not whoever is signed in at sync time" do
    order = described_class.call(user: other_cashier, payload: payload).order

    expect(order.user).to eq(cashier)
    expect(order.payments.sole.processed_by_user).to eq(cashier)
  end

  it "records a promo markdown as a discount on its line" do
    promo = create(:menu_promo, menu_item: burger, location: branch, promo_price_cents: 800, starts_at: 1.day.ago, ends_at: 1.day.from_now)
    line = payload[:items].first.merge(promo_id: promo.id, promo_label: promo.name, promo_discount_cents: 200)

    order = described_class.call(user: cashier, payload: payload(items: [line])).order

    expect(order.order_discounts.sole.amount_cents).to eq(400)
    expect(order.discount_cents).to eq(400)
  end

  it "keeps a modifier that has since been deleted as text on the line" do
    line = payload[:items].first.merge(modifiers: [{ id: SecureRandom.uuid, name: "Gone", price_adjustment_cents: 100 }])

    order = described_class.call(user: cashier, payload: payload(items: [line])).order

    expect(order.order_items.first.order_item_modifiers).to be_empty
    expect(order.order_items.first.notes).to include("no onions").and include("+ Gone")
  end

  it "puts the cash in the cashier's open drawer" do
    treasury = Treasury.create!(company: company, name: "Register", treasury_type: "cash_drawer",
                                balance_cents: 0, opening_balance_cents: 0)
    drawer = CashDrawerSession.create!(user: cashier, treasury: treasury, location: branch,
                                       session_date: BusinessDay.today(location: branch),
                                       opening_float_cents: 0, status: "open")

    order = described_class.call(user: other_cashier, payload: payload(drawer_session_id: drawer.id)).order

    expect(order.payments.sole.cash_drawer_session).to eq(drawer)
  end

  it "records, but does not refuse, a price that differs from the menu" do
    line = payload[:items].first.merge(unit_price_cents: 100)

    result = described_class.call(user: cashier, payload: payload(items: [line]))

    expect(result).to be_success
    expect(result.order.order_items.first.unit_price_cents).to eq(100)
    entry = AuditLogEntry.find_by!(action: "order.offline_price_differs", record_id: result.order.id)
    expect(entry.changes_snapshot["lines"].first).to include("charged_cents" => 100, "menu_cents" => 1000)
  end

  it "leaves the audit trail alone when prices match the menu" do
    described_class.call(user: cashier, payload: payload)

    expect(AuditLogEntry.where(action: "order.offline_price_differs")).to be_none
  end

  it "refuses an order with no items" do
    result = described_class.call(user: cashier, payload: payload(items: []))

    expect(result).not_to be_success
    expect(result.errors.first).to match(/no items/i)
    expect(Order.where(client_uuid: uuid)).to be_none
  end

  it "refuses a table order without a table number, and leaves nothing half-made" do
    result = described_class.call(user: cashier, payload: payload(order_type: "table", table_number: nil))

    expect(result).not_to be_success
    expect(Order.where(client_uuid: uuid)).to be_none
    expect(Payment.count).to eq(0)
  end

  it "refuses a menu item that no longer exists" do
    line = payload[:items].first.merge(menu_item_id: SecureRandom.uuid)

    result = described_class.call(user: cashier, payload: payload(items: [line]))

    expect(result).not_to be_success
    expect(Order.where(client_uuid: uuid)).to be_none
  end
end
