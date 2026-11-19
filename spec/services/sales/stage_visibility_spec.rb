# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sales::StageVisibility do
  let(:company) { create(:company, business_type: "distribution") }
  let(:owner) { create(:user, :owner, company: company) }
  let(:location) { create(:location, company: company) }
  let(:category) { create(:ingredient_category, company: company) }
  let(:ingredient) { create(:ingredient, company: company, ingredient_category: category, name: "Kit", unit: "kg") }
  let(:customer) { create(:customer, company: company, name: "Clinic", customer_type: "regular") }
  let(:shipping_company) { create(:shipping_company, company: company) }
  let(:warehouse_role) do
    Role.create!(company: company, name: "Warehouse", key: "warehouse", permissions: %w[customers:manage sales:dispatch sales:see_all])
  end
  let(:warehouse) { create(:user, company: company, role: "custom", role_id: warehouse_role.id) }

  before do
    Current.company = company
    StockBatch.create!(ingredient: ingredient, location: location, quantity_received: 100,
      quantity_remaining: 100, cost_per_unit_cents: 1_000, received_on: Date.current)
  end

  after { Current.user = nil }

  def configure(role, see: [], notify: [])
    CustomerInvoice::STAGES.each do |stage|
      Sales::StageAccess.create!(role: role, stage: stage, can_see: see.include?(stage), notify: notify.include?(stage))
    end
  end

  def invoice(fulfillment: "delivery", user: owner, salesperson: nil)
    inv = CustomerInvoice.new(company: company, customer: customer, user: user, salesperson: salesperson,
      location: location, invoice_date: Date.current, payment_method: "cash_on_delivery",
      fulfillment_method: fulfillment, shipping_company: (fulfillment == "delivery" ? shipping_company : nil))
    inv.customer_invoice_lines.build(ingredient: ingredient, quantity: 1, unit: ingredient.unit, unit_price_cents: 1_000)
    inv.save!
    inv
  end

  def confirm(inv) = Sales::ConfirmCustomerInvoiceService.new(inv, owner).call

  describe "CustomerInvoice stages" do
    it "describes a confirmed delivery by its shipping step and a pickup as confirmed" do
      delivery = invoice
      expect(delivery.stage).to eq("draft")
      confirm(delivery)
      expect(delivery.reload.stage).to eq("waiting_for_shipping")

      pickup = invoice(fulfillment: "pickup")
      pickup.update!(payment_method: "cash")
      confirm(pickup)
      expect(pickup.reload.stage).to eq("confirmed")

      expect(CustomerInvoice.in_stages(%w[waiting_for_shipping])).to contain_exactly(delivery)
      expect(CustomerInvoice.in_stages(%w[confirmed])).to contain_exactly(pickup)
      expect(CustomerInvoice.in_stages(%w[draft])).to be_empty
    end
  end

  describe "seeing" do
    it "shows every stage to a role the owner hasn't configured" do
      expect(described_class.all_stages?(warehouse)).to be(true)
    end

    it "limits a configured role to its ticked stages" do
      configure(warehouse_role, see: %w[waiting_for_shipping])
      draft = invoice
      waiting = invoice
      confirm(waiting)

      visible = described_class.scope_for(warehouse)
      expect(visible).to contain_exactly(waiting)
      expect(described_class.can_see?(warehouse, draft)).to be(false)
      expect(described_class.can_see?(warehouse, waiting.reload)).to be(true)
    end

    it "always shows invoices you recorded or sold" do
      configure(warehouse_role, see: [])
      mine = invoice(user: warehouse)
      sold = invoice(salesperson: warehouse)

      expect(described_class.scope_for(warehouse)).to contain_exactly(mine, sold)
    end

    it "always shows everything to the owner" do
      expect(described_class.all_stages?(owner)).to be(true)
    end
  end

  describe "notifying" do
    it "tells the roles that ticked notify when an invoice enters that stage" do
      configure(warehouse_role, see: %w[waiting_for_shipping], notify: %w[waiting_for_shipping])
      warehouse
      inv = invoice

      expect { confirm(inv) }.to change { Notification.where(recipient: warehouse).count }.by(1)
      note = Notification.where(recipient: warehouse).last
      expect(note.params["message_key"]).to eq("customer_invoice_stage_entered")
      expect(note.params.dig("message_params", "stage")).to eq("waiting_for_shipping")
    end

    it "doesn't notify a stage the role can't see" do
      configure(warehouse_role, see: [], notify: %w[waiting_for_shipping])
      warehouse
      expect { confirm(invoice) }.not_to(change { Notification.where(recipient: warehouse).count })
    end

    it "doesn't tell people about their own change" do
      configure(warehouse_role, see: %w[waiting_for_shipping shipped], notify: %w[shipped])
      inv = invoice
      confirm(inv)
      Current.user = warehouse

      expect { Sales::DispatchCustomerInvoiceService.new(inv, warehouse).call }
        .not_to(change { Notification.where(recipient: warehouse).count })
    end

    it "notifies nobody by default" do
      warehouse
      expect { confirm(invoice) }.not_to(change { Notification.where(recipient: warehouse).count })
    end
  end
end
