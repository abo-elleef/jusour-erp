# frozen_string_literal: true

# Subscription tracking for SaaS customers. `paid_until` NULL means "no expiry"
# (internal, demo and legacy companies stay unaffected). Raw schema only: no app
# models are touched, so this is safe to run on any database state.
class AddSubscriptionToCompanies < ActiveRecord::Migration[7.1]
  def change
    add_column :companies, :paid_until, :date
    add_column :companies, :plan_name, :string
    add_index :companies, :paid_until
  end
end
