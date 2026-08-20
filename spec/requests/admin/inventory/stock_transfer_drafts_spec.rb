# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Inventory::StockTransfers drafts", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let(:owner) { create(:user, :owner, company: company) }
  let(:kitchen) { create(:location, :central_kitchen, company: company, name: "Central Kitchen") }
  let(:branch) { create(:location, company: company, name: "Branch A") }
  let(:category) { create(:ingredient_category, company: company) }
  let(:ingredient) { create(:ingredient, company: company, ingredient_category: category, quantity_on_hand: 20.0) }
  let(:other_ingredient) { create(:ingredient, company: company, ingredient_category: category, quantity_on_hand: 20.0) }

  before do
    Current.company = company
    sign_in owner
  end

  def base_params(lines)
    {
      stock_transfer: {
        from_location_id: kitchen.id,
        to_location_id: branch.id,
        transferred_on: Date.current.to_s,
        stock_transfer_lines_attributes: lines
      }
    }
  end

  describe "saving a draft" do
    it "keeps a line whose quantity has not been filled in yet" do
      post admin_inventory_stock_transfers_path, params: base_params(
        "0" => { ingredient_id: ingredient.id, quantity_requested_input: "4", unit: ingredient.unit },
        "1" => { ingredient_id: other_ingredient.id, quantity_requested_input: "", unit: other_ingredient.unit }
      ).merge(save_draft: "Save as draft")

      transfer = StockTransfer.last
      expect(transfer.status).to eq("draft")
      # The whole point: nothing silently dropped.
      expect(transfer.stock_transfer_lines.count).to eq(2)
      expect(transfer.stock_transfer_lines.find_by(ingredient: other_ingredient).quantity_requested).to eq(0)
    end

    it "saves a draft with no lines at all" do
      post admin_inventory_stock_transfers_path, params: base_params({}).merge(save_draft: "1")

      expect(StockTransfer.last).to be_draft
      expect(StockTransfer.last.stock_transfer_lines).to be_empty
    end

    it "still drops blank-quantity lines on a real request" do
      post admin_inventory_stock_transfers_path, params: base_params(
        "0" => { ingredient_id: ingredient.id, quantity_requested_input: "4", unit: ingredient.unit },
        "1" => { ingredient_id: other_ingredient.id, quantity_requested_input: "", unit: other_ingredient.unit }
      )

      transfer = StockTransfer.last
      expect(transfer.status).to eq("requested")
      expect(transfer.stock_transfer_lines.count).to eq(1)
    end

    it "keeps the transfer a draft when updated with save_draft" do
      transfer = create(:stock_transfer, :draft, company: company, from_location: kitchen,
        to_location: branch, requested_by: owner)

      patch admin_inventory_stock_transfer_path(transfer), params: base_params(
        "0" => { ingredient_id: ingredient.id, quantity_requested_input: "", unit: ingredient.unit }
      ).merge(save_draft: "1")

      expect(transfer.reload).to be_draft
      expect(transfer.stock_transfer_lines.count).to eq(1)
    end

    it "refuses to promote via the form when a saved placeholder line is untouched" do
      transfer = create(:stock_transfer, :draft, company: company, from_location: kitchen,
        to_location: branch, requested_by: owner)
      good = create(:stock_transfer_line, stock_transfer: transfer, ingredient: ingredient, quantity_requested: 5)
      placeholder = create(:stock_transfer_line, stock_transfer: transfer, ingredient: other_ingredient, quantity_requested: 0)

      # Resubmit both lines unchanged — autosave would skip validating the
      # untouched placeholder, so the service has to catch it.
      patch admin_inventory_stock_transfer_path(transfer), params: base_params(
        "0" => { id: good.id, ingredient_id: ingredient.id, quantity_requested_input: "5", unit: ingredient.unit },
        "1" => { id: placeholder.id, ingredient_id: other_ingredient.id, quantity_requested_input: "", unit: other_ingredient.unit }
      )

      expect(transfer.reload).to be_draft
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "promotes the draft when the edit form is submitted normally" do
      transfer = create(:stock_transfer, :draft, company: company, from_location: kitchen,
        to_location: branch, requested_by: owner)

      patch admin_inventory_stock_transfer_path(transfer), params: base_params(
        "0" => { ingredient_id: ingredient.id, quantity_requested_input: "3", unit: ingredient.unit }
      )

      expect(transfer.reload.status).to eq("requested")
    end
  end

  describe "submitting a draft" do
    let(:draft) do
      create(:stock_transfer, :draft, company: company, from_location: kitchen,
        to_location: branch, requested_by: owner)
    end

    it "promotes a complete draft to requested" do
      create(:stock_transfer_line, stock_transfer: draft, ingredient: ingredient, quantity_requested: 5)

      post submit_admin_inventory_stock_transfer_path(draft)

      expect(draft.reload.status).to eq("requested")
    end

    it "refuses a draft with a placeholder line and names the ingredient" do
      create(:stock_transfer_line, stock_transfer: draft, ingredient: ingredient, quantity_requested: 5)
      create(:stock_transfer_line, stock_transfer: draft, ingredient: other_ingredient, quantity_requested: 0)

      post submit_admin_inventory_stock_transfer_path(draft)

      expect(draft.reload).to be_draft
      expect(flash[:alert]).to include(other_ingredient.name)
    end

    it "refuses an empty draft" do
      post submit_admin_inventory_stock_transfer_path(draft)

      expect(draft.reload).to be_draft
      expect(flash[:alert]).to be_present
    end

    it "rolls transferred_on forward so the ledger posts on the submit day" do
      draft.update_columns(transferred_on: 5.days.ago.to_date)
      create(:stock_transfer_line, stock_transfer: draft, ingredient: ingredient, quantity_requested: 5)

      post submit_admin_inventory_stock_transfer_path(draft)

      expect(draft.reload.transferred_on).to eq(Date.current)
    end

    it "rejects submitting something that is not a draft" do
      transfer = create(:stock_transfer, company: company, from_location: kitchen,
        to_location: branch, requested_by: owner)
      create(:stock_transfer_line, stock_transfer: transfer, ingredient: ingredient, quantity_requested: 5)

      post submit_admin_inventory_stock_transfer_path(transfer)

      expect(transfer.reload.status).to eq("requested")
      expect(flash[:alert]).to be_present
    end
  end

  describe "discarding" do
    it "destroys a draft" do
      draft = create(:stock_transfer, :draft, company: company, from_location: kitchen,
        to_location: branch, requested_by: owner)

      expect { delete admin_inventory_stock_transfer_path(draft) }
        .to change(StockTransfer, :count).by(-1)
    end

    it "refuses to destroy a submitted transfer" do
      transfer = create(:stock_transfer, company: company, from_location: kitchen,
        to_location: branch, requested_by: owner)

      expect { delete admin_inventory_stock_transfer_path(transfer) }
        .not_to change(StockTransfer, :count)
      expect(flash[:alert]).to be_present
    end
  end

  describe "a draft is not shippable" do
    it "cannot be sent" do
      draft = create(:stock_transfer, :draft, company: company, from_location: kitchen,
        to_location: branch, requested_by: owner)

      expect(draft.can_send?).to be(false)
    end
  end
end
