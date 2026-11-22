# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Online order payment methods and proof" do
  include ActiveJob::TestHelper
  include ActionDispatch::TestProcess::FixtureFile
  include OpenDrawerHelpers

  let(:company) { create(:company) }
  let(:branch) { online_branch(company) }
  let(:cashier) { create(:user, company: company, role: "cashier") }
  let(:item) { create(:menu_item, company: company, name: "Koshary", base_price_cents: 5_000) }
  let(:png) { fixture_file_upload("storefront_product.png", "image/png") }
  let(:text_file) { fixture_file_upload("not_an_image.txt", "text/plain") }

  before do
    Current.company = company
    create(:location_menu_item, location: branch, menu_item: item, available: true)
  end

  def offer(method, requires_proof: false, pay_to: nil, enabled: true)
    branch.online_payment_methods.create!(payment_method: method, enabled: enabled,
                                          requires_proof: requires_proof, pay_to: pay_to)
  end

  def submit(**overrides)
    OnlineOrders::SubmitService.call(location: branch, params: online_params(item: item, **overrides))
  end

  describe "what a branch offers" do
    it "offers cash only when nothing was set up" do
      expect(branch.offered_online_payment_methods.map(&:payment_method)).to eq(["cash"])
    end

    it "offers the enabled methods in a fixed order" do
      offer("vodafone_cash", requires_proof: true)
      offer("cash", enabled: false)
      offer("instapay")

      expect(branch.reload.offered_online_payment_methods.map(&:payment_method)).to eq(%w[instapay vodafone_cash])
    end

    it "refuses to turn every method off" do
      branch.assign_attributes(online_payment_methods_attributes: [
        { payment_method: "cash", enabled: "0" }, { payment_method: "instapay", enabled: "0" }
      ])

      expect(branch).not_to be_valid
      expect(branch.errors[:base]).to include(I18n.t("admin.locations.online_ordering.errors.no_payment_method"))
    end

    it "never asks for a screenshot for cash" do
      expect(branch.online_payment_methods.build(payment_method: "cash", requires_proof: true)).not_to be_valid
    end
  end

  describe OnlineOrders::SubmitService do
    it "keeps cash orders working with no method sent" do
      result = submit

      expect(result).to be_ok
      expect(result.request.payment_method).to eq("cash")
      expect(result.request).not_to be_prepaid
    end

    it "refuses a method the branch doesn't offer" do
      offer("instapay", requires_proof: true)

      expect(submit(payment_method: "vodafone_cash").error).to eq(:bad_payment_method)
    end

    it "refuses cash once the branch turned it off" do
      offer("cash", enabled: false)
      offer("instapay", requires_proof: true)

      expect(submit.error).to eq(:bad_payment_method)
    end

    it "refuses a pay-first method without a screenshot, or with something that isn't one" do
      offer("instapay", requires_proof: true)

      expect(submit(payment_method: "instapay").error).to eq(:missing_proof)
      expect(submit(payment_method: "instapay", payment_proof_image: text_file).error).to eq(:bad_proof)
      expect(OnlineOrderRequest.count).to eq(0)
    end

    it "saves a pay-first order with its screenshot" do
      offer("instapay", requires_proof: true)

      request = submit(payment_method: "instapay", payment_proof_image: png).request

      expect(request.payment_method).to eq("instapay")
      expect(request).to be_prepaid
      expect(request.payment_proof_image).to be_attached
    end

    it "takes a pay-on-receipt wallet order without a screenshot" do
      offer("vodafone_cash")

      request = submit(payment_method: "vodafone_cash").request

      expect(request).not_to be_prepaid
      expect(request.payment_proof_image).not_to be_attached
    end
  end

  describe OnlineOrders::AcceptService do
    before { open_drawer_for(cashier, location: branch) }

    it "records a prepaid order as paid by its method in the cashier's drawer" do
      offer("instapay", requires_proof: true)
      request = submit(payment_method: "instapay", payment_proof_image: png).request

      order = OnlineOrders::AcceptService.call(request: request, user: cashier).order.reload

      expect(order).to be_fully_paid
      payment = order.payments.sole
      expect(payment.payment_method).to eq("instapay")
      expect(payment.amount_cents).to eq(order.total_cents)
      expect(payment.processed_by_user).to eq(cashier)
      expect(payment.cash_drawer_session).to eq(cashier.open_cash_drawer_session(location: branch))
    end

    it "leaves a pay-on-receipt order unpaid" do
      offer("vodafone_cash")
      request = submit(payment_method: "vodafone_cash").request

      order = OnlineOrders::AcceptService.call(request: request, user: cashier).order

      expect(order.payments).to be_empty
    end

    it "records the new total when the cashier accepts a price change" do
      offer("instapay", requires_proof: true)
      request = submit(payment_method: "instapay", payment_proof_image: png).request
      item.update!(base_price_cents: 6_000)

      expect(OnlineOrders::AcceptService.call(request: request, user: cashier).error).to eq(:price_changed)
      order = OnlineOrders::AcceptService.call(request: request.reload, user: cashier, confirm_price_change: true).order.reload

      expect(order.payments.sole.amount_cents).to eq(12_000)
      expect(order).to be_fully_paid
    end
  end
end
