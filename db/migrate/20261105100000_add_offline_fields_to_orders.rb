# frozen_string_literal: true

# Orders rung up while the internet was down are created in the browser and pushed
# to the server later. `client_uuid` is what makes that push safe to repeat — a
# retry after a dropped response finds the order it already made instead of making
# a second one. `offline_number` is the number the customer's receipt carried, so a
# printed ticket can still be matched to the order once the server has numbered it.
class AddOfflineFieldsToOrders < ActiveRecord::Migration[7.1]
  def change
    add_column :orders, :client_uuid, :string
    add_column :orders, :offline_number, :string
    add_index :orders, %i[company_id client_uuid],
              unique: true,
              where: "client_uuid IS NOT NULL",
              name: "index_orders_on_company_id_and_client_uuid"
  end
end
