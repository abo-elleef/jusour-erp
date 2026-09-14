# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Vendor credit notes", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { Current.company }
  let(:owner) { create(:user, :owner, company: company) }
  let(:supplier) { Supplier.create!(name: "Fresh Farms", company: company) }
  let(:location) { create(:location, :central_kitchen, company: company) }
  let(:category) { IngredientCategory.create!(name: "Produce", position: 1, company: company) }
  let!(:ingredient) do
    Ingredient.create!(name: "Tomatoes", ingredient_category: category, unit: "kg",
      reorder_threshold: 1, cost_per_unit_cents: 250, quantity_on_hand: 0, company: company)
  end

  before { sign_in owner }

  it "renders the new form" do
    get new_admin_inventory_vendor_credit_note_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("vendor_credit_note[vendor_credit_note_lines_attributes]")
  end

  it "creates a draft from the line total, deriving the unit price" do
    expect {
      post admin_inventory_vendor_credit_notes_path, params: {
        vendor_credit_note: {
          supplier_id: supplier.id,
          credit_note_date: Date.current,
          kind: "price_adjustment",
          notes: "",
          vendor_credit_note_lines_attributes: {
            "0" => {
              ingredient_id: ingredient.id,
              unit_id: ingredient.unit_ref&.id,
              quantity: "10",
              line_total_pounds: "12.30",
              position: "0",
              _destroy: "false"
            }
          }
        }
      }
    }.to change(VendorCreditNote, :count).by(1)

    credit_note = VendorCreditNote.order(:created_at).last
    expect(response).to redirect_to(admin_inventory_vendor_credit_note_path(credit_note))
    expect(credit_note).to be_draft
    expect(credit_note.vendor_credit_note_lines.sole.line_total_cents).to eq(1_230)
    expect(credit_note.vendor_credit_note_lines.sole.unit_price_cents).to eq(123)
    expect(credit_note.total_cents).to eq(1_230)
  end

  context "with a saved credit note" do
    let(:kind) { "price_adjustment" }
    let(:note_location) { nil }
    let!(:credit_note) do
      VendorCreditNote.create!(
        supplier: supplier, user: owner, credit_note_date: Date.current, company: company,
        kind: kind, location: note_location,
        vendor_credit_note_lines_attributes: {
          "0" => { ingredient_id: ingredient.id, unit_id: ingredient.unit_ref&.id,
                   quantity: "10", line_total_pounds: "12.30", position: "0" }
        }
      )
    end

    it "renders the index" do
      get admin_inventory_vendor_credit_notes_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(credit_note.credit_note_number)
    end

    it "renders the show page with its lines" do
      get admin_inventory_vendor_credit_note_path(credit_note)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Tomatoes")
    end

    it "confirms the credit note and posts it to the AP ledger" do
      expect {
        post confirm_admin_inventory_vendor_credit_note_path(credit_note)
      }.to change(TreasuryTransaction, :count).by(1)
        .and change(JournalEntry, :count).by(1)

      expect(response).to redirect_to(admin_inventory_vendor_credit_note_path(credit_note))
      expect(credit_note.reload).to be_confirmed
      expect(TreasuryTransaction.order(:created_at).last.amount_cents).to eq(-1_230)
    end

    it "leaves stock alone for a price adjustment" do
      expect {
        post confirm_admin_inventory_vendor_credit_note_path(credit_note)
      }.not_to change(StockAdjustment, :count)

      expect(ingredient.reload.quantity_on_hand).to eq(0)
    end

    context "when the note returns goods" do
      let(:kind) { "goods_return" }
      let(:note_location) { location }

      before do
        IngredientLocation.create!(ingredient: ingredient, location: location, quantity_on_hand: 25)
        ingredient.update_columns(quantity_on_hand: 25)
        StockBatch.create!(ingredient: ingredient, location: location, quantity_received: 25,
          quantity_remaining: 25, cost_per_unit_cents: 250, received_on: Date.current)
      end

      it "takes the returned quantity back out of stock at that location" do
        expect {
          post confirm_admin_inventory_vendor_credit_note_path(credit_note)
        }.to change(StockAdjustment, :count).by(1)

        adjustment = StockAdjustment.order(:created_at).last
        expect(adjustment.adjustment_type).to eq("vendor_credit_note")
        expect(adjustment.location).to eq(location)
        expect(adjustment.quantity_delta).to eq(-10)

        expect(IngredientLocation.find_by(ingredient: ingredient, location: location).quantity_on_hand).to eq(15)
        expect(StockBatch.sole.quantity_remaining).to eq(15)
      end

      it "still reduces the supplier AP balance" do
        post confirm_admin_inventory_vendor_credit_note_path(credit_note)
        expect(TreasuryTransaction.order(:created_at).last.amount_cents).to eq(-1_230)
      end
    end

    it "rejects a goods return with no location" do
      note = VendorCreditNote.new(
        supplier: supplier, user: owner, credit_note_date: Date.current, company: company,
        kind: "goods_return",
        vendor_credit_note_lines_attributes: {
          "0" => { ingredient_id: ingredient.id, quantity: "1", line_total_pounds: "1.00", position: "0" }
        }
      )
      expect(note).not_to be_valid
      expect(note.errors[:location]).to be_present
    end

    it "voids a draft credit note" do
      patch void_admin_inventory_vendor_credit_note_path(credit_note)
      expect(response).to redirect_to(admin_inventory_vendor_credit_notes_path)
      expect(credit_note.reload).to be_void
    end
  end
end
