# frozen_string_literal: true

# Step 1 (enabler): a company's industry profile + per-feature overrides. The
# profile sets sensible module defaults (restaurant vs distribution); overrides
# let a single company flip an individual feature without changing its profile.
class AddBusinessTypeToCompanies < ActiveRecord::Migration[7.1]
  def change
    add_column :companies, :business_type, :string, default: "restaurant", null: false
    add_column :companies, :feature_overrides, :jsonb, default: {}, null: false
  end
end
