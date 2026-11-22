# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin modifier group public name", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { Current.company }
  let(:owner) { create(:user, :owner, company: company, wages_account_code: 2501) }
  let(:group) { ModifierGroup.create!(company: company, name: "حار/عادي") }

  before { sign_in owner }

  it "offers the public name field on the edit page" do
    get edit_admin_modifier_group_path(group)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('name="modifier_group[public_name]"')
  end

  it "saves the public name and shows it on the group page" do
    patch admin_modifier_group_path(group), params: { modifier_group: { public_name: "Hot level" } }

    expect(group.reload.public_name).to eq("Hot level")
    follow_redirect!
    expect(response.body).to include("Hot level")
  end
end
