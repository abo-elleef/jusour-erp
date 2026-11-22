# frozen_string_literal: true

require "rails_helper"

# An option that was ordered can't be deleted, so the admin deactivates it. It must
# then disappear for cashiers, the offline register, the call center and online
# customers, while old orders keep it.
RSpec.describe "Inactive modifier options" do
  let(:company) { create(:company) }
  let(:branch) { create(:location, company: company) }
  let(:cashier) { create(:user, company: company, role: "cashier") }
  let(:burger) { create(:menu_item, company: company, name: "Burger", base_price_cents: 10_000) }
  let(:size) { ModifierGroup.create!(company: company, name: "Size", required: true, multi_select: false) }
  let!(:single) { size.modifiers.create!(company: company, name: "Single", price_adjustment_cents: 0) }
  let!(:double) { size.modifiers.create!(company: company, name: "Double", price_adjustment_cents: 4_000, active: false) }
  let(:sauce) { ModifierGroup.create!(company: company, name: "Sauce", required: true, multi_select: false) }
  let!(:old_sauce) { sauce.modifiers.create!(company: company, name: "Old sauce", active: false) }

  before do
    Current.company = company
    create(:location_menu_item, location: branch, menu_item: burger, available: true)
    burger.menu_item_modifier_groups.create!(modifier_group: size, position: 1)
    burger.menu_item_modifier_groups.create!(modifier_group: sauce, position: 2)
  end

  it "is active by default" do
    expect(size.modifiers.create!(company: company, name: "Triple")).to be_active
  end

  describe "online menu / call center quote (strict)" do
    def quote(ids)
      Orders::QuoteService.call(location: branch, items: [{ menu_item_id: burger.id, modifier_ids: ids }])
    end

    it "refuses a line with an inactive option instead of quietly dropping it" do
      expect(quote([double.id]).errors).to eq(0 => :unavailable)
    end

    it "does not require a group whose options are all inactive" do
      result = quote([single.id])

      expect(result).to be_ok
      expect(result.subtotal_cents).to eq(10_000)
    end
  end

  it "leaves an inactive option off a POS line (non-strict)" do
    line = Orders::ResolveLine.call(location: branch, menu_item_id: burger.id, modifier_ids: [single.id, double.id])

    expect(line.modifiers).to eq([single])
  end

  it "hides inactive options, and groups with none left, from the offline register" do
    snapshot = Orders::OfflineSnapshotService.call(user: cashier, location: branch, workstation: nil, csrf_token: "t")
    groups = snapshot[:menu][:items].find { |item| item[:id] == burger.id }[:modifier_groups]

    expect(groups.map { |g| g[:name] }).to eq(["Size"])
    expect(groups.first[:modifiers].map { |m| m[:name] }).to eq(["Single"])
  end

  it "hides inactive options from the public menu popup" do
    json = JSON.parse(ApplicationController.helpers.extend(PublicOrderingHelper, PosModifierHelper)
                                           .orderable_item_json(burger, branch))

    expect(json["groups"].map { |g| g["name"] }).to eq(["Size"])
    expect(json["groups"].first["modifiers"].map { |m| m["name"] }).to eq(["Single"])
    expect(json["pricing"]["groups"].first["modifiers"].map { |m| m["id"] }).to eq([single.id])
  end
end
