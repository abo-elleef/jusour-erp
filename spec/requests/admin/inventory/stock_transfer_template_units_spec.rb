# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Stock transfer units from a template", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let(:owner) { create(:user, :owner, company: company) }
  let(:kitchen) { create(:location, :central_kitchen, company: company) }
  let(:branch) { create(:location, company: company) }
  let(:category) { create(:ingredient_category, company: company) }
  let!(:ingredient) do
    create(:ingredient, company: company, ingredient_category: category, name: "Tomatoes", unit: "kg")
  end

  let(:template) do
    # An active template needs at least one line, so activate after seeding.
    t = StockTransferTemplate.create!(company: company, name: "Weekly produce",
      default_from_location: kitchen, default_to_location: branch, active: false)
    t.stock_transfer_template_lines.create!(ingredient: ingredient, unit: ingredient.unit,
      default_quantity: 5)
    t.update!(active: true)
    t
  end

  before do
    Current.company = company
    sign_in owner
  end

  def transfer_from_template
    tr = create(:stock_transfer, company: company, from_location: kitchen, to_location: branch,
      requested_by: owner, stock_transfer_template: template)
    line = create(:stock_transfer_line, stock_transfer: tr, ingredient: ingredient,
      quantity_requested: 5, unit: ingredient.unit, position: 0)
    [tr, line]
  end

  def manual_transfer
    tr = create(:stock_transfer, company: company, from_location: kitchen, to_location: branch,
      requested_by: owner)
    line = create(:stock_transfer_line, stock_transfer: tr, ingredient: ingredient,
      quantity_requested: 5, unit: ingredient.unit, position: 0)
    [tr, line]
  end

  describe "the model rule" do
    it "locks units when built from a template" do
      tr, _ = transfer_from_template
      expect(tr).to be_from_template
      expect(tr).to be_units_locked
    end

    it "leaves units free on a hand-built transfer" do
      tr, _ = manual_transfer
      expect(tr).not_to be_from_template
      expect(tr.units_locked?).to be(false)
    end

    it "unlocks if the template is later deleted" do
      tr, _ = transfer_from_template
      template.destroy!
      expect(tr.reload.units_locked?).to be(false)
    end
  end

  describe "the new form" do
    it "records the template so the lock survives a save" do
      get new_admin_inventory_stock_transfer_path(template_id: template.id)

      expect(response.body).to include('name="stock_transfer[stock_transfer_template_id]"')
      expect(response.body).to include(template.id)
    end

    it "fixes the unit and explains who can change it" do
      get new_admin_inventory_stock_transfer_path(template_id: template.id)

      expect(response.body).to include(I18n.t("inventory.stock_transfers.unit_locked_hint"))
      # The template's line posts its unit through a hidden field, with no picker.
      expect(response.body).to match(/<input[^>]*type="hidden"[^>]*\[0\]\[unit\]/)
      expect(response.body).not_to match(/<select[^>]*\[0\]\[unit\]/)
    end

    it "still gives a hand-added line its own unit picker" do
      get new_admin_inventory_stock_transfer_path(template_id: template.id)

      # The NEW_RECORD row is the template for lines the requester adds; those
      # aren't part of the transfer template, so they keep the choice.
      expect(response.body).to match(/<select[^>]*\[NEW_RECORD\]\[unit\]/)
    end

    it "leaves the unit selectable with no template" do
      get new_admin_inventory_stock_transfer_path

      expect(response.body).not_to include(I18n.t("inventory.stock_transfers.unit_locked_hint"))
    end
  end

  describe "the edit form" do
    it "keeps the unit fixed on a template-built transfer" do
      tr, _ = transfer_from_template

      get edit_admin_inventory_stock_transfer_path(tr)

      expect(response.body).to include(I18n.t("inventory.stock_transfers.unit_locked_hint"))
    end

    it "keeps the unit selectable on a hand-built transfer" do
      tr, _ = manual_transfer

      get edit_admin_inventory_stock_transfer_path(tr)

      expect(response.body).not_to include(I18n.t("inventory.stock_transfers.unit_locked_hint"))
    end
  end

  describe "server-side enforcement" do
    # A disabled or read-only input is a hint, not a guarantee — and `unit` drives
    # the base-unit conversion, so a switched unit would silently corrupt quantities.
    it "ignores a submitted unit change on a template-built transfer" do
      tr, line = transfer_from_template
      other_unit = create(:ingredient, company: company, ingredient_category: category,
        name: "Other", unit: "liters").unit

      patch admin_inventory_stock_transfer_path(tr), params: {
        stock_transfer: {
          from_location_id: kitchen.id, to_location_id: branch.id,
          transferred_on: tr.transferred_on,
          stock_transfer_lines_attributes: {
            "0" => { id: line.id, ingredient_id: ingredient.id,
                     quantity_requested_input: "5", unit: other_unit }
          }
        }
      }

      expect(line.reload.unit).to eq(ingredient.unit)
    end

    it "accepts a unit change on a hand-built transfer" do
      tr, line = manual_transfer
      # Give the ingredient a real second unit so this exercises the positive path
      # rather than skipping.
      box = Unit.find_or_create_by!(company: company, name: "box")
      ingredient.ingredient_units.create!(company: company, unit_ref: box, base_units_per_unit: 12)
      alt = ingredient.reload.available_units.find { |u| u != ingredient.unit }
      expect(alt).to be_present

      patch admin_inventory_stock_transfer_path(tr), params: {
        stock_transfer: {
          from_location_id: kitchen.id, to_location_id: branch.id,
          transferred_on: tr.transferred_on,
          stock_transfer_lines_attributes: {
            "0" => { id: line.id, ingredient_id: ingredient.id,
                     quantity_requested_input: "5", unit: alt }
          }
        }
      }

      expect(line.reload.unit).to eq(alt)
    end

    it "still lets a hand-added line choose its unit on a template transfer" do
      tr, _ = transfer_from_template
      fresh = create(:ingredient, company: company, ingredient_category: category,
        name: "Added By Hand", unit: "liters")

      patch admin_inventory_stock_transfer_path(tr), params: {
        stock_transfer: {
          from_location_id: kitchen.id, to_location_id: branch.id,
          transferred_on: tr.transferred_on,
          stock_transfer_lines_attributes: {
            "1" => { ingredient_id: fresh.id, quantity_requested_input: "2", unit: fresh.unit }
          }
        }
      }

      added = tr.reload.stock_transfer_lines.find_by(ingredient_id: fresh.id)
      expect(added&.unit).to eq(fresh.unit)
    end
  end
end
