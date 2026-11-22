# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Deactivating a modifier option", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { Current.company }
  let(:owner) { create(:user, :owner, company: company, wages_account_code: 2501) }
  let(:group) { ModifierGroup.create!(company: company, name: "Size") }
  let!(:double) { group.modifiers.create!(name: "Double", price_adjustment_cents: 3_500) }

  before { sign_in owner }

  it "flips active from the group page and shows the Inactive badge" do
    patch admin_modifier_group_modifier_path(group, double), params: { toggle_active: 1 }

    expect(double.reload).not_to be_active
    follow_redirect!
    expect(response.body).to include(I18n.t("menu.modifiers.inactive_badge"))
    expect(response.body).to include(I18n.t("menu.modifiers.activate"))

    patch admin_modifier_group_modifier_path(group, double), params: { toggle_active: 1 }
    expect(double.reload).to be_active
  end

  it "saves the Active checkbox from the edit form" do
    patch admin_modifier_group_modifier_path(group, double), params: { modifier: { name: "Double", active: "0" } }

    expect(double.reload).not_to be_active
  end
end
