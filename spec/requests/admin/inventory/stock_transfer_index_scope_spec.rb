# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Inventory::StockTransfers index scoping", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let(:owner) { create(:user, :owner, company: company) }
  let(:kitchen) { create(:location, :central_kitchen, company: company, name: "Central Kitchen") }
  let(:branch) { create(:location, company: company, name: "Branch A") }
  let(:elsewhere) { create(:location, company: company, name: "Branch Z") }

  before do
    Current.company = company
    sign_in owner
  end

  def transfer(status_trait = nil, number:, on: Date.current, from: kitchen, to: branch)
    attrs = { company: company, from_location: from, to_location: to,
              requested_by: owner, transferred_on: on, transfer_number: number }
    status_trait ? create(:stock_transfer, status_trait, **attrs) : create(:stock_transfer, **attrs)
  end

  describe "the default landing view" do
    it "shows only transfers that still need action" do
      transfer(number: "ST-OPEN-1")
      transfer(:awaiting_receipt, number: "ST-OPEN-2")
      transfer(:partially_received, number: "ST-OPEN-3")
      transfer(:draft, number: "ST-DRAFT-1")
      transfer(:completed, number: "ST-DONE-1", on: 3.days.ago.to_date)
      create(:stock_transfer, company: company, from_location: kitchen, to_location: branch,
        requested_by: owner, status: "cancelled", transfer_number: "ST-VOID-1")

      get admin_inventory_stock_transfers_path

      expect(response.body).to include("ST-OPEN-1", "ST-OPEN-2", "ST-OPEN-3")
      expect(response.body).not_to include("ST-DRAFT-1")
      expect(response.body).not_to include("ST-VOID-1")
      # Completed-today only; this one is 3 days old.
      expect(response.body).not_to include("ST-DONE-1")
    end

    it "orders the queue oldest-first so the most overdue is on top" do
      transfer(:awaiting_receipt, number: "ST-NEW", on: Date.current)
      transfer(:awaiting_receipt, number: "ST-OLD", on: 10.days.ago.to_date)

      get admin_inventory_stock_transfers_path

      expect(response.body.index("ST-OLD")).to be < response.body.index("ST-NEW")
    end

    it "flags an awaiting_receipt transfer past the aging window" do
      transfer(:awaiting_receipt, number: "ST-STALE", on: (StockTransfer::AGING_RECEIPT_DAYS + 3).days.ago.to_date)

      get admin_inventory_stock_transfers_path

      expect(response.body).to include(I18n.t("inventory.stock_transfers.aging_badge",
        count: StockTransfer::AGING_RECEIPT_DAYS + 3))
    end

    it "appends today's completed transfers below the queue" do
      transfer(number: "ST-OPEN-1")
      transfer(:completed, number: "ST-DONE-TODAY", on: Date.current)
      transfer(:completed, number: "ST-DONE-OLD", on: 2.days.ago.to_date)

      get admin_inventory_stock_transfers_path

      expect(response.body).to include(I18n.t("inventory.stock_transfers.completed_today"))
      expect(response.body).to include("ST-DONE-TODAY")
      expect(response.body).not_to include("ST-DONE-OLD")
    end

    it "reads as all-clear rather than empty when nothing is open" do
      transfer(:completed, number: "ST-DONE-1", on: 5.days.ago.to_date)

      get admin_inventory_stock_transfers_path

      expect(response.body).to include(I18n.t("inventory.stock_transfers.empty_open"))
    end
  end

  describe "scope tabs" do
    it "today shows every status dated today and nothing older" do
      transfer(:completed, number: "ST-TODAY", on: Date.current)
      transfer(:awaiting_receipt, number: "ST-YESTERDAY", on: 1.day.ago.to_date)

      get admin_inventory_stock_transfers_path(scope: "today")

      expect(response.body).to include("ST-TODAY")
      expect(response.body).not_to include("ST-YESTERDAY")
    end

    it "all shows drafts and closed transfers too" do
      transfer(:draft, number: "ST-DRAFT-1")
      transfer(:completed, number: "ST-DONE-1", on: 9.days.ago.to_date)

      get admin_inventory_stock_transfers_path(scope: "all")

      expect(response.body).to include("ST-DRAFT-1", "ST-DONE-1")
    end

    it "falls back to the open queue for an unknown scope" do
      transfer(:draft, number: "ST-DRAFT-1")
      transfer(number: "ST-OPEN-1")

      get admin_inventory_stock_transfers_path(scope: "bogus")

      expect(response.body).to include("ST-OPEN-1")
      expect(response.body).not_to include("ST-DRAFT-1")
    end

    it "the draft status tab lists drafts" do
      transfer(:draft, number: "ST-DRAFT-1")
      transfer(number: "ST-OPEN-1")

      get admin_inventory_stock_transfers_path(status: "draft")

      expect(response.body).to include("ST-DRAFT-1")
      expect(response.body).not_to include("ST-OPEN-1")
    end
  end

  describe "location filter" do
    it "matches transfers on either side of the move" do
      transfer(number: "ST-FROM-KITCHEN", from: kitchen, to: branch)
      transfer(number: "ST-TO-KITCHEN", from: branch, to: kitchen)
      transfer(number: "ST-UNRELATED", from: branch, to: elsewhere)

      get admin_inventory_stock_transfers_path(location_id: kitchen.id)

      expect(response.body).to include("ST-FROM-KITCHEN", "ST-TO-KITCHEN")
      expect(response.body).not_to include("ST-UNRELATED")
    end
  end
end
