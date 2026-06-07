# frozen_string_literal: true

class ReceiptsController < ApplicationController
  skip_before_action :authenticate_user!
  before_action :set_current_company

  def show
    @order = Order.unscoped.find_by!(receipt_token: params[:token])
    render layout: "receipt"
  end

  private

  def set_current_company
    order = Order.unscoped.find_by(receipt_token: params[:token])
    Current.company = order&.company
  end
end
