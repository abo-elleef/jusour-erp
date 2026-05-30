# frozen_string_literal: true

class ReceiptsController < ApplicationController
  skip_before_action :authenticate_user!

  def show
    @order = Order.find_by!(receipt_token: params[:token])
    render layout: "receipt"
  end
end
