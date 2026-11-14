# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sales::PaymentApproval do
  let(:company) { create(:company, business_type: "distribution") }
  let(:owner) { create(:user, :owner, company: company) }
  let(:manager) { create(:user, company: company, role: "manager") } # holds sales:confirm_payments
  let(:location) { create(:location, company: company) }
  let(:customer) { create(:customer, company: company) }
  let(:treasury) do
    Treasury.create!(name: "Wallet", treasury_type: "bank", balance_cents: 0, opening_balance_cents: 0, company: company)
  end
  let(:payment_method) { create(:sales_payment_method, company: company, treasury: treasury, name: "Vodafone Cash Saif") }

  before { Current.company = company }

  def custom_user(*permissions)
    role = Role.create!(company: company, name: "R #{SecureRandom.hex(2)}", key: "r_#{SecureRandom.hex(3)}",
      permissions: permissions)
    create(:user, company: company, role: "custom", role_id: role.id)
  end

  def invoice
    CustomerInvoice.create!(company: company, customer: customer, user: owner, location: location,
      invoice_date: Date.current, payment_method: "online", sales_payment_method: payment_method)
  end

  context "when the method has no approvers" do
    it "falls back to everyone holding sales:confirm_payments" do
      manager
      inv = invoice
      expect(described_class.approvers_for(inv)).to include(manager)
      expect(described_class.can_approve?(manager, inv)).to be(true)
    end

    it "does not let someone without the permission approve" do
      expect(described_class.can_approve?(custom_user("customers:manage"), invoice)).to be(false)
    end
  end

  context "when the method has approvers" do
    let(:saif) { custom_user("customers:manage") } # no sales:confirm_payments at all

    before { payment_method.approvers << saif }

    it "routes approval to exactly those people" do
      manager
      inv = invoice
      expect(described_class.approvers_for(inv)).to contain_exactly(saif)
      expect(described_class.can_approve?(saif, inv)).to be(true)
    end

    it "blocks a confirm_payments holder who isn't assigned to this method" do
      expect(described_class.can_approve?(manager, invoice)).to be(false)
    end

    it "always lets the owner approve" do
      expect(described_class.can_approve?(owner, invoice)).to be(true)
    end

    it "falls back to the permission holders once every assigned approver is inactive" do
      manager
      saif.update!(active: false)
      inv = invoice
      expect(described_class.approvers_for(inv)).to include(manager)
      expect(described_class.can_approve?(manager, inv)).to be(true)
    end

    it "counts the assigned approver as an approver for the nav link" do
      expect(described_class.approver_anywhere?(saif)).to be(true)
      expect(described_class.approver_anywhere?(custom_user("customers:manage"))).to be(false)
    end
  end

  it "notifies only the method's approvers when a payment is submitted" do
    manager
    saif = custom_user("customers:manage")
    payment_method.approvers << saif
    inv = invoice

    expect { Sales::NotifyService.deliver_payment_pending(inv) }.to change(Notification, :count).by(1)
    expect(Notification.last.recipient).to eq(saif)
  end
end
