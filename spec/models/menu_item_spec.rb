# frozen_string_literal: true

require "rails_helper"

RSpec.describe MenuItem, type: :model do
  subject { build(:menu_item) }

  it { is_expected.to validate_presence_of(:name) }
  it { is_expected.to validate_numericality_of(:base_price_cents).is_greater_than_or_equal_to(0) }
  it { is_expected.to validate_inclusion_of(:tax_category).in_array(MenuItem::TAX_CATEGORIES) }

  describe "image variants" do
    it "defines pos and public_menu variants" do
      expect(MenuItemImageVariants::VARIANTS).to eq(pos: 320, public_menu: 256)
    end
  end
end
