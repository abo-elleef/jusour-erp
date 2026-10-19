# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sales::NotifyService do
  let(:company) { create(:company) }

  before { Current.company = company }

  describe ".recipients_for" do
    it "resolves by the actual permission grant, not a hardcoded role name" do
      manager = create(:user, company: company, role: "manager")
      cashier = create(:user, company: company, role: "cashier")

      recipients = described_class.recipients_for("sales:confirm_payments")

      expect(recipients).to include(manager)
      expect(recipients).not_to include(cashier)
    end

    it "excludes an inactive user even if their role holds the permission" do
      inactive_manager = create(:user, company: company, role: "manager", active: false)

      expect(described_class.recipients_for("sales:confirm_payments")).not_to include(inactive_manager)
    end

    it "follows a company's own customized role permissions, not the built-in defaults" do
      custom_role = Role.create!(company: company, key: "custom_sales_rep", name: "Custom Sales Rep",
        permissions: %w[sales:confirm_payments])
      user = create(:user, company: company, role: "custom", role_id: custom_role.id)

      expect(described_class.recipients_for("sales:confirm_payments")).to include(user)
      expect(custom_role).to be_present
    end
  end

  describe ".deliver_payment_pending" do
    let(:manager) { create(:user, company: company, role: "manager") }
    let(:cashier) { create(:user, company: company, role: "cashier") }
    let(:customer) { create(:customer, company: company) }
    let(:location) { create(:location, company: company) }
    let(:invoice) do
      CustomerInvoice.create!(company: company, customer: customer, user: manager, location: location,
        invoice_date: Date.current, payment_method: "on_account")
    end

    it "notifies every user holding sales:confirm_payments, and only them" do
      manager
      cashier

      expect { described_class.deliver_payment_pending(invoice) }.to change(Notification, :count).by(1)

      notification = Notification.last
      expect(notification.recipient).to eq(manager)
      expect(notification.notification_type).to eq("sales")
      expect(notification.params["message_key"]).to eq("customer_invoice_payment_pending")
      expect(notification.customer_invoice).to eq(invoice)
    end
  end
end
