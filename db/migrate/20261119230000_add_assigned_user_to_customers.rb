# frozen_string_literal: true

# The salesperson who owns this customer (Bazzar slice E). A sales rep without
# sales:see_all sees only the customers assigned to them — see
# Sales::OwnershipScope. Nullable: unassigned customers are visible to managers
# only until someone assigns them. Filled for existing rows by the rake task
# `sales:backfill_customer_owners`, not here.
class AddAssignedUserToCustomers < ActiveRecord::Migration[7.1]
  def change
    add_reference :customers, :assigned_user, type: :uuid, foreign_key: { to_table: :users }, index: true
  end
end
