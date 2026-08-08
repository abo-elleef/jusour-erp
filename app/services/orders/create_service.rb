# frozen_string_literal: true

module Orders
  class CreateService
    def self.call(user:, customer: nil, order_type: "pickup", table_number: nil, delivery_address: nil, location: nil, workstation: nil)
      new(
        user: user,
        customer: customer,
        order_type: order_type,
        table_number: table_number,
        delivery_address: delivery_address,
        location: location,
        workstation: workstation
      ).call
    end

    def initialize(user:, customer: nil, order_type: "pickup", table_number: nil, delivery_address: nil, location: nil, workstation: nil)
      @user = user
      @customer = customer
      @order_type = order_type
      @table_number = table_number
      @delivery_address = delivery_address
      @location = location
      @workstation = workstation
    end

    def call
      Order.create!(
        user: @user,
        customer: @customer,
        location: @location,
        workstation: @workstation,
        status: "draft",
        order_type: @order_type,
        table_number: @table_number,
        delivery_address: @delivery_address
      )
    end
  end
end
