# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin customer blocking", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let(:manager) { create(:user, :manager, company: company, name: "Mona Manager") }
  # Admin access, but not customers:manage.
  let(:accountant) { create(:user, company: company, role: "accountant") }
  let(:customer) { create(:customer, company: company) }

  before { Current.company = company }

  context "with customers:manage" do
    before { sign_in manager }

    it "offers the block form on the customer page" do
      get admin_customer_path(customer), headers: { "Turbo-Frame" => "customer_tab" }
      expect(response.body).to include(I18n.t("customers.block.block"), block_admin_customer_path(customer))
    end

    it "blocks with a reason, then shows who and why" do
      post block_admin_customer_path(customer), params: { blocked_reason: "Three fake orders" }

      expect(response).to redirect_to(admin_customer_path(customer))
      customer.reload
      expect(customer).to be_blocked
      expect(customer.blocked_by).to eq(manager)
      expect(customer.blocked_reason).to eq("Three fake orders")

      get admin_customer_path(customer), headers: { "Turbo-Frame" => "customer_tab" }
      expect(response.body).to include(I18n.t("customers.block.blocked_heading"), "Three fake orders", "Mona Manager")
      expect(response.body).to include(unblock_admin_customer_path(customer))

      # The page header flags it on every tab.
      get admin_customer_path(customer)
      expect(response.body).to include(I18n.t("customers.block.blocked_badge"))
    end

    it "needs a reason" do
      post block_admin_customer_path(customer), params: { blocked_reason: "  " }

      expect(response).to redirect_to(admin_customer_path(customer))
      expect(flash[:alert]).to eq(I18n.t("flash.customer.block_reason_required"))
      expect(customer.reload).not_to be_blocked
    end

    it "unblocks" do
      customer.block!(by: manager, reason: "Spam")
      post unblock_admin_customer_path(customer)
      expect(customer.reload).not_to be_blocked
    end
  end

  context "without customers:manage" do
    before { sign_in accountant }

    it "hides the buttons and refuses the actions" do
      get admin_customer_path(customer), headers: { "Turbo-Frame" => "customer_tab" }
      expect(response.body).not_to include(block_admin_customer_path(customer))

      post block_admin_customer_path(customer), params: { blocked_reason: "Nope" }
      expect(customer.reload).not_to be_blocked
    end
  end
end
