# frozen_string_literal: true

class AddStaffMealUserToOrders < ActiveRecord::Migration[7.1]
  def change
    add_reference :orders, :staff_meal_user, foreign_key: { to_table: :users }, type: :uuid, null: true
  end
end
