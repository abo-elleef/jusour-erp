# frozen_string_literal: true

module Inventory
  # Records a landed-cost line on a shipment as a cash-out Expense (which posts to
  # the treasury + ledger via the Expense callbacks) and links it to a ShipmentCost
  # that joins the shipment's cost pool.
  class RecordShipmentCostService
    class Error < StandardError; end

    LANDED_CATEGORY = "Landed costs"

    def initialize(shipment:, user:, cost_type:, amount_cents:, treasury:, incurred_on: Date.current, description: nil)
      @shipment = shipment
      @user = user
      @cost_type = cost_type
      @amount_cents = amount_cents.to_i
      @treasury = treasury
      @incurred_on = incurred_on
      @description = description
    end

    def call
      raise Error, I18n.t("inventory.import_shipments.errors.invalid_amount", default: "Cost amount must be positive.") if @amount_cents <= 0
      raise Error, I18n.t("inventory.import_shipments.errors.treasury_required", default: "A treasury is required.") if @treasury.blank?

      cost = nil
      ActiveRecord::Base.transaction do
        expense = Expense.create!(
          company: @shipment.company,
          expense_category: landed_category,
          user: @user,
          treasury: @treasury,
          amount_cents: @amount_cents,
          expense_date: @incurred_on,
          description: description_text
        )
        cost = ShipmentCost.create!(
          import_shipment: @shipment, user: @user, treasury: @treasury,
          cost_type: @cost_type, amount_cents: @amount_cents,
          incurred_on: @incurred_on, description: @description, expense: expense
        )
      end
      cost
    end

    private

    def landed_category
      ExpenseCategory.find_or_create_by!(name: LANDED_CATEGORY, company: @shipment.company) do |c|
        c.category_type = "other"
      end
    end

    def description_text
      @description.presence || "#{@cost_type.to_s.humanize} — #{@shipment.shipment_number}"
    end
  end
end
