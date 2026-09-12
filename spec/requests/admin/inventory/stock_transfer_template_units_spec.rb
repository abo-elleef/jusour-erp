# frozen_string_literal: true

require "rails_helper"

# Units on a template-built transfer are deliberately NOT locked. An earlier
# version fixed each line to the template's unit and refused changes server-side;
# that was reverted, because the requester is the one holding the goods and a
# template can be out of date. The guard rail is now an audit trail, not a block:
# every unit change is accepted and recorded.
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

  # A second real unit on the ingredient, so unit-change tests exercise the
  # positive path instead of being rejected as an unavailable unit.
  def alternate_unit
    box = Unit.find_or_create_by!(company: company, name: "box")
    ingredient.ingredient_units.create!(company: company, unit_ref: box, base_units_per_unit: 12)
    ingredient.reload.available_units.find { |u| u != ingredient.unit }
  end

  def patch_line_unit(transfer, line, unit)
    patch admin_inventory_stock_transfer_path(transfer), params: {
      stock_transfer: {
        from_location_id: kitchen.id, to_location_id: branch.id,
        transferred_on: transfer.transferred_on,
        stock_transfer_lines_attributes: {
          "0" => { id: line.id, ingredient_id: ingredient.id,
                   quantity_requested_input: "5", unit: unit }
        }
      }
    }
  end

  def unit_audits
    AuditLogEntry.where(action: "stock_transfer_line.unit_changed")
  end

  describe "template provenance" do
    it "remembers the template it was built from" do
      tr, _ = transfer_from_template
      expect(tr).to be_from_template
    end

    it "is blank on a hand-built transfer" do
      tr, _ = manual_transfer
      expect(tr).not_to be_from_template
    end

    it "forgets the template once it is deleted" do
      tr, _ = transfer_from_template
      template.destroy!
      expect(tr.reload).not_to be_from_template
    end
  end

  describe "the new form" do
    it "records the template so it survives a save" do
      get new_admin_inventory_stock_transfer_path(template_id: template.id)

      expect(response.body).to include('name="stock_transfer[stock_transfer_template_id]"')
      expect(response.body).to include(template.id)
    end

    it "gives the template's own line a unit picker rather than a fixed value" do
      get new_admin_inventory_stock_transfer_path(template_id: template.id)

      expect(response.body).to match(/<select[^>]*\[0\]\[unit\]/)
      expect(response.body).not_to match(/<input[^>]*type="hidden"[^>]*\[0\]\[unit\]/)
    end

    it "gives a hand-added line its own unit picker" do
      get new_admin_inventory_stock_transfer_path(template_id: template.id)

      # The NEW_RECORD row is the template for lines the requester adds.
      expect(response.body).to match(/<select[^>]*\[NEW_RECORD\]\[unit\]/)
    end
  end

  describe "the edit form" do
    it "keeps the unit editable on a template-built transfer" do
      tr, _ = transfer_from_template

      get edit_admin_inventory_stock_transfer_path(tr)

      expect(response.body).to match(/<select[^>]*\[0\]\[unit\]/)
    end

    it "keeps the unit editable on a hand-built transfer" do
      tr, _ = manual_transfer

      get edit_admin_inventory_stock_transfer_path(tr)

      expect(response.body).to match(/<select[^>]*\[0\]\[unit\]/)
    end
  end

  describe "saving a unit change" do
    it "accepts a unit change on a template-built transfer" do
      tr, line = transfer_from_template
      alt = alternate_unit
      expect(alt).to be_present

      patch_line_unit(tr, line, alt)

      expect(line.reload.unit).to eq(alt)
    end

    it "accepts a unit change on a hand-built transfer" do
      tr, line = manual_transfer
      alt = alternate_unit
      expect(alt).to be_present

      patch_line_unit(tr, line, alt)

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

  # `unit` drives the base-unit conversion, so a switched unit silently rescales
  # quantities. Nothing blocks that any more — this trail is what makes it
  # traceable afterwards, so it is the part worth guarding.
  describe "the audit trail that replaced the lock" do
    it "records who changed a line's unit, and from what to what" do
      tr, line = transfer_from_template
      alt = alternate_unit
      was = line.unit

      expect { patch_line_unit(tr, line, alt) }.to change(unit_audits, :count).by(1)

      entry = unit_audits.order(:created_at).last
      expect(entry.record_type).to eq("StockTransferLine")
      expect(entry.record_id).to eq(line.id)
      expect(entry.user).to eq(owner)
      expect(entry.changes_snapshot["from_unit"]).to eq(was)
      expect(entry.changes_snapshot["to_unit"]).to eq(alt)
      expect(entry.changes_snapshot["ingredient"]).to eq(ingredient.name)
    end

    it "records nothing when the unit is left alone" do
      tr, line = transfer_from_template

      expect { patch_line_unit(tr, line, line.unit) }.not_to change(unit_audits, :count)
    end
  end
end
