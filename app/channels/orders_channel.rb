# frozen_string_literal: true

class OrdersChannel < ApplicationCable::Channel
  def subscribed
    stream_from "kitchen"
  end
end
