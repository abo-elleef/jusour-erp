# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261119230100_grant_sales_see_all_to_existing_roles")

# Deploying slice E must change nothing: every role that reaches the sales or
# leads area today keeps seeing everything.
RSpec.describe GrantSalesSeeAllToExistingRoles do
  let(:company) { create(:company, business_type: "distribution") }

  before { Current.company = company }

  def role_with(name, permissions)
    role = Role.create!(company: company, name: name, permissions: permissions)
    # Start from the pre-migration state, whatever the seeds hold today.
    Role.connection.execute("UPDATE roles SET permissions = permissions - 'sales:see_all' WHERE id = '#{role.id}'")
    role
  end

  def migrate!
    ActiveRecord::Migration.suppress_messages { described_class.new.up }
  end

  it "grants sales:see_all to every role holding any sales-area permission, and only those" do
    granted = {
      "Customers" => %w[customers:manage],
      "Leads viewer" => %w[leads:view],
      "Approver" => %w[sales:confirm_payments],
      "Warehouse" => %w[sales:dispatch],
      "Checker" => %w[sales:complete_shipping]
    }.to_h { |name, perms| [name, role_with(name, perms)] }
    untouched = [role_with("Cashier-ish", %w[pos:access]), role_with("Lead reports only", %w[leads:reports])]

    migrate!

    granted.each_value { |role| expect(role.reload.permission_keys).to include("sales:see_all") }
    untouched.each { |role| expect(role.reload.permission_keys).not_to include("sales:see_all") }
  end

  it "is idempotent" do
    role = role_with("Customers", %w[customers:manage])
    2.times { migrate! }
    expect(role.reload.permission_keys.count("sales:see_all")).to eq(1)
  end
end
