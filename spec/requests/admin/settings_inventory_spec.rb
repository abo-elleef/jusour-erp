# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin settings inventory", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let(:owner) { create(:user, :owner, company: company) }

  before do
    Current.company = company
    sign_in owner
  end

  it "defaults to restricting transfers to source stock" do
    expect(Setting.restrict_stock_transfers_to_source?).to be(true)
  end

  it "lets the owner turn restrict mode off" do
    patch admin_settings_path, params: { restrict_stock_transfers_to_source: "0" }

    expect(response).to redirect_to(admin_settings_path)
    expect(CompanySetting.find_by!(company: company).restrict_stock_transfers_to_source).to be(false)
  end

  it "lets the owner turn restrict mode back on" do
    Setting.set("restrict_stock_transfers_to_source", false)

    patch admin_settings_path, params: { restrict_stock_transfers_to_source: "1" }

    expect(CompanySetting.find_by!(company: company).restrict_stock_transfers_to_source).to be(true)
  end
end
