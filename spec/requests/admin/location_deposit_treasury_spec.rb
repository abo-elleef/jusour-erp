# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Setting a branch's drawer banking treasury", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let!(:branch) { create(:location, company: company, name: "Main Branch") }
  let(:owner) { create(:user, :owner, company: company) }
  let!(:safe) do
    Treasury.create!(company: company, name: "Main Safe", treasury_type: "safe",
      balance_cents: 0, opening_balance_cents: 0)
  end

  before do
    Current.company = company
    sign_in owner
  end

  describe "the location page" do
    it "names the treasury once it is set" do
      branch.update!(deposit_treasury: safe)

      get admin_location_path(branch)

      expect(response.body).to include(I18n.t("admin.locations.fields.deposit_treasury"))
      expect(response.body).to include(safe.name)
    end

    it "flags a branch that has none, since the fallback is silent otherwise" do
      get admin_location_path(branch)

      expect(response.body).to include(I18n.t("admin.locations.deposit_treasury_unset"))
    end
  end

  it "offers the treasury on the edit form" do
    get edit_admin_location_path(branch)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("admin.locations.fields.deposit_treasury"))
    expect(response.body).to include(safe.name)
  end

  it "saves the choice" do
    patch admin_location_path(branch), params: {
      location: { name: branch.name, deposit_treasury_id: safe.id }
    }

    expect(branch.reload.deposit_treasury).to eq(safe)
  end

  it "can be cleared back to the company default" do
    branch.update!(deposit_treasury: safe)

    patch admin_location_path(branch), params: {
      location: { name: branch.name, deposit_treasury_id: "" }
    }

    expect(branch.reload.deposit_treasury).to be_nil
  end
end
