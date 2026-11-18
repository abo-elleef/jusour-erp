# frozen_string_literal: true

require "rails_helper"

# Category#menu_visibility: most categories show on both the register and the
# public menu; some on one of them only.
RSpec.describe Menus::ForLocation do
  let(:company) { create(:company) }
  let(:branch) { create(:location, company: company) }

  before { Current.company = company }

  def item_in(visibility, name)
    category = create(:category, company: company, menu_visibility: visibility)
    create(:menu_item, company: company, category: category, name: name).tap do |item|
      create(:location_menu_item, location: branch, menu_item: item, available: true)
    end
  end

  let!(:both) { item_in("both", "Burger") }
  let!(:pos_only) { item_in("pos", "Staff meal") }
  let!(:public_only) { item_in("public", "Online box") }

  it "leaves public-menu-only categories off the POS" do
    result = described_class.call(location: branch, channel: :pos)

    expect(result.menu_items).to contain_exactly(both, pos_only)
    expect(result.categories).to contain_exactly(both.category, pos_only.category)
  end

  it "leaves POS-only categories off the public menu" do
    result = described_class.call(location: branch, channel: :public)

    expect(result.menu_items).to contain_exactly(both, public_only)
    expect(result.categories).to contain_exactly(both.category, public_only.category)
  end
end
