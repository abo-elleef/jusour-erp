# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Roles duplicate", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let(:owner) { create(:user, :owner, company: company) }
  let!(:source) do
    Role.create!(company: company, name: "Floor Supervisor", permissions: %w[customers:manage orders:view])
  end

  before do
    Current.company = company
    sign_in owner
  end

  it "shows a Duplicate link for each role" do
    get admin_roles_path

    expect(response.body).to include(CGI.escapeHTML(new_admin_role_path(copy_from: source.id)))
  end

  it "pre-fills the new role form with the source role's name and permissions" do
    get new_admin_role_path(copy_from: source.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("roles.copy_name", name: "Floor Supervisor"))
    expect(response.body).to match(/value="customers:manage"[^>]*checked/)
    expect(response.body).to match(/value="orders:view"[^>]*checked/)
    expect(response.body).not_to match(/value="menu:manage"[^>]*checked/)
  end

  it "warns that a copy of a name-dependent built-in role loses name-based behaviour" do
    manager_role = Role.unscoped.find_by!(company_id: company.id, key: "manager")

    get new_admin_role_path(copy_from: manager_role.id)

    expect(response.body).to include(CGI.escapeHTML(I18n.t("roles.copy_name_warning.lost.manager")))
  end

  it "does not warn when copying a custom role" do
    get new_admin_role_path(copy_from: source.id)

    expect(response.body).not_to include(CGI.escapeHTML(I18n.t("roles.copy_name_warning.advice", name: "Floor Supervisor")))
  end

  it "creates the copy with the edited permissions and stage settings, but no staff" do
    create(:user, company: company, role_id: source.id)
    Sales::StageAccess.create!(role: source, stage: "draft", can_see: true, notify: true)
    Sales::StageAccess.create!(role: source, stage: "shipped", can_see: false, notify: false)

    post admin_roles_path, params: {
      copy_from: source.id,
      role: { name: "Floor Supervisor Plus", permissions: %w[customers:manage orders:view menu:manage] }
    }

    expect(response).to redirect_to(admin_roles_path)

    copy = Role.find_by!(name: "Floor Supervisor Plus")
    expect(copy.permission_keys).to match_array(%w[customers:manage orders:view menu:manage])
    expect(copy.built_in).to be(false)
    expect(copy.users).to be_empty
    expect(copy.stage_accesses.pluck(:stage, :can_see, :notify))
      .to contain_exactly(["draft", true, true], ["shipped", false, false])
    expect(source.reload.users.count).to eq(1)
  end

  it "lets a copied role with stage settings be deleted" do
    copy = Role.create!(company: company, name: "Temp copy", permissions: %w[customers:manage])
    Sales::StageAccess.create!(role: copy, stage: "draft", can_see: true, notify: false)

    delete admin_role_path(copy)

    expect(Role.exists?(copy.id)).to be(false)
    expect(Sales::StageAccess.where(role_id: copy.id)).to be_empty
  end
end
