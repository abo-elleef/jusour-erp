# frozen_string_literal: true

class OrdersChannel < ApplicationCable::Channel
  def subscribed
    stream_from "kitchen_#{current_user.company_id}"
  end
end
