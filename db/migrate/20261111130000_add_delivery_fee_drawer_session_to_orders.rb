# frozen_string_literal: true

# The driver keeps the delivery fee. On a cash order they keep it out of what the
# customer paid; on an InstaPay / Vodafone Cash order the cashier hands it over
# from the drawer. Either way the drawer ends up short by the fee, so each fee is
# a payout from the drawer session that took the order's first payment.
class AddDeliveryFeeDrawerSessionToOrders < ActiveRecord::Migration[7.1]
  def change
    add_reference :orders, :delivery_fee_drawer_session, type: :uuid, null: true, index: true,
                  foreign_key: { to_table: :cash_drawer_sessions }
  end
end
