# frozen_string_literal: true

class ReceiptMailer < ApplicationMailer
  def order_receipt(order, recipient)
    @order = order
    mail(to: recipient, subject: "Receipt for #{order.order_number}")
  end
end
