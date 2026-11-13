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
    expect(order.order_number).to be_present
    expect(order.placed_at).to be_present
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

  describe "delivery" do
    def delivery(overrides = {})
      payload(order_type: "delivery", customer_name: "Mona", customer_phone: "01012345678",
              delivery_address: "12 Nile St, Apt 4").merge(overrides)
    end

    it "creates the customer and their address, and puts both on the order" do
      order = nil
      expect { order = described_class.call(user: cashier, payload: delivery).order }
        .to change(Customer, :count).by(1)

      expect(order.order_type).to eq("delivery")
      expect(order.delivery_address).to eq("12 Nile St, Apt 4")
      expect(order.customer).to have_attributes(name: "Mona", phone: "01012345678")
      expect(order.customer.addresses.sole.address).to eq("12 Nile St, Apt 4")
    end

    it "reuses a customer the system already has, matched by phone" do
      existing = Customer.create!(name: "Mona K", phone: "01012345678")
      existing.addresses.create!(address: "12 Nile St, Apt 4")

      expect { @order = described_class.call(user: cashier, payload: delivery).order }.not_to change(Customer, :count)

      expect(@order.customer).to eq(existing)
      expect(existing.addresses.count).to eq(1)
    end

    it "matches the customer's second phone too, and ignores spaces and dashes" do
      existing = Customer.create!(name: "Mona K", phone: "01099999999", phone_secondary: "01012345678")

      order = described_class.call(user: cashier, payload: delivery(customer_phone: "010 1234-5678")).order

      expect(order.customer).to eq(existing)
      expect(existing.addresses.pluck(:address)).to eq(["12 Nile St, Apt 4"])
    end

    it "adds a new address to a known customer without replacing their default" do
      existing = Customer.create!(name: "Mona K", phone: "01012345678")
      existing.addresses.create!(address: "Old address")

      described_class.call(user: cashier, payload: delivery)

      expect(existing.addresses.ordered.map(&:address)).to eq(["Old address", "12 Nile St, Apt 4"])
    end

    it "refuses delivery without an address or without a phone, leaving no customer behind" do
      no_address = described_class.call(user: cashier, payload: delivery(delivery_address: " "))
      no_phone = described_class.call(user: cashier, payload: delivery(customer_phone: ""))

      expect(no_address).not_to be_success
      expect(no_phone).not_to be_success
      expect(Customer.count).to eq(0)
      expect(Order.where(client_uuid: uuid)).to be_none
    end

    it "does not attach a customer to table or pickup orders" do
      order = described_class.call(user: cashier, payload: payload(customer_phone: "01012345678", delivery_address: "x")).order

      expect(order.customer).to be_nil
      expect(order.delivery_address).to be_nil
    end
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

  describe "an order carried over from the online register" do
    let(:draft) do
      Order.create!(user: cashier, location: branch, order_type: "pickup").tap do |order|
        order.order_items.create!(menu_item: burger, quantity: 2, unit_price_cents: 1000)
      end
    end

    it "discards the draft it replaces, with an audit entry, so the sale is not left behind unpaid" do
      result = described_class.call(user: cashier, payload: payload(replaces_order_id: draft.id))

      expect(result).to be_success
      expect(Order.exists?(draft.id)).to be(false)
      entry = AuditLogEntry.find_by(action: "order.discard", record_id: draft.id)
      expect(entry.changes_snapshot).to include("replaced_by_order_id" => result.order.id)
    end

    it "leaves a draft that was paid or sent to the kitchen in the meantime" do
      draft.payments.create!(payment_method: "cash", amount_cents: 100, tip_cents: 0, status: "completed", processed_by_user: cashier)
      sent = Order.create!(user: cashier, location: branch, order_type: "pickup", kitchen_sent_at: Time.current)

      described_class.call(user: cashier, payload: payload(replaces_order_id: draft.id))
      described_class.call(user: cashier, payload: payload(client_uuid: SecureRandom.uuid, replaces_order_id: sent.id))

      expect(Order.exists?(draft.id)).to be(true)
      expect(Order.exists?(sent.id)).to be(true)
    end

    it "still syncs when the draft is already gone" do
      result = described_class.call(user: cashier, payload: payload(replaces_order_id: SecureRandom.uuid))

      expect(result).to be_success
    end
  end

  describe "a table someone else took while the internet was down" do
    let(:branch) { create(:location, company: company, table_service: true, table_count: 6) }

    let!(:holder) do
      order = create(:order, user: other_cashier, company: company, location: branch,
                             order_type: "table", table_number: "3", status: "submitted")
      create(:order_item, order: order)
      order
    end

    it "still syncs the paid order, and flags the clash for a manager" do
      result = described_class.call(user: cashier, payload: payload(order_type: "table", table_number: "3"))

      expect(result).to be_success
      expect(result.order.table_number).to eq("3")
      expect(result.order).to be_fully_paid
      expect(Order.table_orders(branch)["3"]).to contain_exactly(holder, result.order)

      entry = AuditLogEntry.find_by(action: "order.offline_table_clash")
      expect(entry.record).to eq(result.order)
      expect(entry.changes_snapshot).to include("table_number" => "3", "other_order_id" => holder.id)
    end

    it "flags nothing when the table was free" do
      described_class.call(user: cashier, payload: payload(order_type: "table", table_number: "4"))

      expect(AuditLogEntry.where(action: "order.offline_table_clash")).to be_empty
    end

    it "keeps the busy-table rule for ordinary orders" do
      order = Order.new(user: cashier, company: company, location: branch, order_type: "table", table_number: "3")

      expect(order).not_to be_valid
      expect(order.errors[:table_number]).to be_present
    end
  end
end
