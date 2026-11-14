# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Sales::PaymentMethods", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company, business_type: "distribution") }
  let(:owner) { create(:user, :owner, company: company) }
  let(:treasury) do
    Treasury.create!(name: "CIB", treasury_type: "bank", balance_cents: 0, opening_balance_cents: 0, company: company)
  end

  before do
    Current.company = company
    sign_in owner
  end

  it "creates a method that needs approval by default" do
    post admin_sales_payment_methods_path,
      params: { sales_payment_method: { name: "InstaPay", treasury_id: treasury.id, active: "1" } }

    expect(response).to redirect_to(admin_sales_payment_methods_path)
    expect(Sales::PaymentMethod.find_by!(name: "InstaPay").requires_approval).to be(true)
  end

  it "creates a card machine that settles on confirm" do
    post admin_sales_payment_methods_path,
      params: { sales_payment_method: { name: "Card machine", treasury_id: treasury.id, active: "1",
                                        requires_approval: "0" } }

    expect(Sales::PaymentMethod.find_by!(name: "Card machine").requires_approval).to be(false)
  end

  it "shows how each method settles on the list" do
    create(:sales_payment_method, company: company, treasury: treasury, name: "Card machine", requires_approval: false)
    create(:sales_payment_method, company: company, treasury: treasury, name: "InstaPay")

    get admin_sales_payment_methods_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("sales.payment_methods.settles_on_confirm"))
    expect(response.body).to include(I18n.t("sales.payment_methods.needs_approval"))
  end

  describe "approvers" do
    let(:saif) { create(:user, company: company, role: "manager", name: "Saif") }
    let(:naggar) { create(:user, company: company, role: "manager", name: "El-Naggar") }
    let(:cashier) { create(:user, company: company, role: "cashier", name: "Cashier") }

    it "saves the ticked approvers and lists them" do
      post admin_sales_payment_methods_path, params: { sales_payment_method: {
        name: "Vodafone Cash Saif", treasury_id: treasury.id, active: "1", approver_ids: ["", saif.id] } }

      method = Sales::PaymentMethod.find_by!(name: "Vodafone Cash Saif")
      expect(method.approvers).to contain_exactly(saif)

      get admin_sales_payment_methods_path
      expect(response.body).to include("Saif")
    end

    it "replaces the set on edit, and clears it when nothing is ticked" do
      method = create(:sales_payment_method, company: company, treasury: treasury, name: "CIB")
      method.approvers << saif

      patch admin_sales_payment_method_path(method), params: { sales_payment_method: { approver_ids: ["", naggar.id] } }
      expect(method.reload.approvers).to contain_exactly(naggar)

      patch admin_sales_payment_method_path(method), params: { sales_payment_method: { approver_ids: [""] } }
      expect(method.reload.approvers).to be_empty
    end

    it "ignores someone who can't open the sales area" do
      post admin_sales_payment_methods_path, params: { sales_payment_method: {
        name: "QNB", treasury_id: treasury.id, active: "1", approver_ids: [cashier.id] } }

      expect(Sales::PaymentMethod.find_by!(name: "QNB").approvers).to be_empty
    end
  end
end
