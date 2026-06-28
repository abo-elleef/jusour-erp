# frozen_string_literal: true

module Pos
  class CustomersController < ApplicationController
    include PosLocationScoped

    layout "pos"

    before_action :require_pos_access!
    before_action :set_customer

    def update
      authorize @customer, :update_contact?

      if @customer.update(customer_params)
        @order = load_current_order
        render "pos/customers/update", formats: [:turbo_stream]
      else
        @order = load_current_order
        @customer_form_errors = @customer.errors
        render "pos/customers/update_error", formats: [:turbo_stream]
      end
    end

    private

    def set_customer
      @customer = Customer.find(params[:id])
      raise Pundit::NotAuthorizedError unless @customer.company_id == Current.company.id
    end

    def customer_params
      params.require(:customer).permit(
        :name, :phone, :phone_secondary,
        addresses_attributes: %i[id label address is_default _destroy]
      )
    end

    def load_current_order
      return unless session[:current_order_id]

      Order.find_by(id: session[:current_order_id], status: "draft")
    end

    def require_pos_access!
      return if current_user&.can_access_pos?

      flash[:alert] = t("flash.pos_access")
      redirect_to root_path
    end
  end
end
